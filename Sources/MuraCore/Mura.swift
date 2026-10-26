import CryptoKit
import Foundation

struct Args {
    static let valued: Set<String> = ["--date", "--title", "--note", "--file", "--size", "--out"]
    static let flags: Set<String> = ["--stdin", "--important", "--no-apply", "--clear", "--no-schedule"]

    var positional: [String] = []
    var values: [String: String] = [:]
    var set: Set<String> = []

    init(_ raw: [String]) throws {
        var i = 0
        while i < raw.count {
            let arg = raw[i]
            if Args.valued.contains(arg) {
                guard i + 1 < raw.count else { throw MuraError.usage("\(arg) needs a value") }
                values[arg] = raw[i + 1]
                i += 2
                continue
            }
            if Args.flags.contains(arg) { set.insert(arg) } else if arg.hasPrefix("--"), arg != "--" {
                throw MuraError.usage("Unknown option \(arg). Run `mura help`.")
            } else { positional.append(arg) }
            i += 1
        }
    }

    func indexes(count: Int) throws -> [Int] {
        guard !positional.isEmpty else { throw MuraError.usage("Give item numbers, e.g. `mura done 2 3` (see `mura show`)") }
        return try positional.map { raw in
            guard let n = Int(raw), n >= 1, n <= count else {
                throw MuraError.usage("No item #\(raw); this day has \(count) item(s)")
            }
            return n - 1
        }
    }
}

public struct Output {
    public let json: String
    public let exitCode: Int32
}

/// Every command answers with one JSON object: {"ok": true, "command": ..., "data": {...}}
/// or {"ok": false, "command": ..., "error": {"code": ..., "message": ...}}.
public final class Mura {
    let home: Home
    let desktop: Desktop
    let env: [String: String]
    let now: Date
    var warnings: [String] = []

    public init(home: Home, desktop: Desktop, env: [String: String], now: Date = Date()) {
        self.home = home
        self.desktop = desktop
        self.env = env
        self.now = now
    }

    public func run(_ argv: [String], stdin: () -> String = { String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "" }) -> Output {
        let command = argv.first ?? "help"
        var body: [String: Any] = ["command": command]
        var code: Int32 = 0
        do {
            let args = try Args(Array(argv.dropFirst()))
            body["data"] = try dispatch(command, args, stdin: stdin)
            body["ok"] = true
        } catch let error as MuraError {
            body["ok"] = false
            body["error"] = ["code": error.code, "message": error.message]
            code = error.code == "usage" ? 2 : 1
        } catch {
            body["ok"] = false
            body["error"] = ["code": "internal", "message": "\(error)"]
            code = 1
        }
        if !warnings.isEmpty { body["warnings"] = warnings }
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return Output(json: String(data: data, encoding: .utf8) ?? "{}", exitCode: code)
    }

    var calendarist: Calendarist {
        get throws {
            let config = try home.config()
            if let name = config.timezone {
                guard let zone = TimeZone(identifier: name) else { throw MuraError.usage("Unknown timezone '\(name)' in config") }
                return Calendarist(timeZone: zone, now: now)
            }
            return Calendarist(timeZone: .current, now: now)
        }
    }

    private func dispatch(_ command: String, _ args: Args, stdin: () -> String) throws -> Any {
        switch command {
        case "help", "--help", "-h": return Mura.help
        case "show": return try describe(try key(args))
        case "list": return try list()
        case "plan": return try plan(args, stdin: stdin)
        case "add": return try add(args)
        case "done", "undone": return try edit(args) { day, i in day.items[i].done = command == "done" }
        case "rm": return try remove(args)
        case "title": return try edit(args, needsIndex: false) { day, _ in day.title = args.set.contains("--clear") ? nil : args.positional.joined(separator: " ") }
        case "note": return try edit(args, needsIndex: false) { day, _ in day.note = args.set.contains("--clear") ? nil : args.positional.joined(separator: " ") }
        case "clear": return try edit(args, needsIndex: false) { day, _ in day = Day() }
        case "render": return try render(args)
        case "apply": return try home.withLock { try apply(try key(args), onlyIfChanged: false) }
        case "tick": return try tick()
        case "undo": return try home.withLock { try undo() }
        case "setup": return try setup(args)
        case "schedule": return try schedule(args)
        case "config": return try config(args)
        case "doctor": return try doctor()
        default: throw MuraError.usage("Unknown command '\(command)'. Run `mura help`.")
        }
    }

    // MARK: days

    private func key(_ args: Args) throws -> String { try calendarist.resolve(args.values["--date"]) }

    private func chinese(_ day: Day) throws -> Bool {
        switch try home.config().lang ?? "auto" {
        case "zh": return true
        case "en": return false
        default: return day.isEmpty ? (Locale.preferredLanguages.first ?? "").hasPrefix("zh") : day.containsCJK
        }
    }

    private func describe(_ key: String) throws -> [String: Any] {
        let day = try home.loadDay(key)
        let cal = try calendarist
        var out: [String: Any] = [
            "date": key,
            "label": cal.label(for: key, chinese: try chinese(day)),
            "isToday": key == cal.today,
            "file": home.dayURL(key).path,
            "items": day.items.enumerated().map { i, item in
                ["n": i + 1, "text": item.text, "done": item.done, "important": item.important] as [String: Any]
            },
        ]
        out["title"] = day.title ?? NSNull()
        out["note"] = day.note ?? NSNull()
        return out
    }

    private func list() throws -> [String: Any] {
        let cal = try calendarist
        return ["today": cal.today, "days": try home.dayKeys().map { key -> [String: Any] in
            let day = try home.loadDay(key)
            return ["date": key, "items": day.items.count, "done": day.items.filter(\.done).count]
        }]
    }

    private func plan(_ args: Args, stdin: () -> String) throws -> [String: Any] {
        let text: String
        if let file = args.values["--file"] {
            text = try String(contentsOfFile: (file as NSString).expandingTildeInPath, encoding: .utf8)
        } else if args.set.contains("--stdin") {
            text = stdin()
        } else {
            text = args.positional.map { "- \($0)" }.joined(separator: "\n")
        }
        var day = Day.parse(text)
        if let title = args.values["--title"] { day.title = title }
        if let note = args.values["--note"] { day.note = note }
        guard !day.isEmpty else { throw MuraError.usage("Nothing to plan. Pass items as arguments, --stdin or --file.") }
        return try write(args) { $0 = day }
    }

    private func add(_ args: Args) throws -> [String: Any] {
        guard !args.positional.isEmpty else { throw MuraError.usage("Usage: mura add \"item\" [\"item\" …] [--important] [--date D]") }
        return try write(args) { day in
            for text in args.positional {
                guard var item = Day.parseItem(text) else { continue }
                if args.set.contains("--important") { item.important = true }
                day.items.append(item)
            }
        }
    }

    private func remove(_ args: Args) throws -> [String: Any] {
        try write(args) { day in
            let doomed = Set(try args.indexes(count: day.items.count))
            day.items = day.items.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        }
    }

    private func edit(_ args: Args, needsIndex: Bool = true, _ change: @escaping (inout Day, Int) -> Void) throws -> [String: Any] {
        try write(args) { day in
            if needsIndex {
                for i in try args.indexes(count: day.items.count) { change(&day, i) }
            } else {
                change(&day, 0)
            }
        }
    }

    /// Saves a day and, if it is today, puts it on the wallpaper right away.
    private func write(_ args: Args, _ change: (inout Day) throws -> Void) throws -> [String: Any] {
        try home.withLock {
            let key = try key(args)
            var day = try home.loadDay(key)
            try change(&day)
            try home.saveDay(day, key: key)
            var out = try describe(key)
            let schedule = Schedule(home: home, env: env)
            if key != (try calendarist.today) {
                out["wallpaper"] = ["applied": false, "reason": "not today", "autoSwitch": schedule.installed]
                if !schedule.installed { warnings.append("The daily switch is not installed, so \(key) will not appear by itself. Run `mura setup` (or `mura apply --date \(key)` on that day).") }
            } else if args.set.contains("--no-apply") {
                out["wallpaper"] = ["applied": false, "reason": "--no-apply"]
            } else {
                out["wallpaper"] = try apply(key, onlyIfChanged: false)
            }
            return out
        }
    }

    // MARK: rendering

    private func fingerprint(_ day: Day, label: String, canvases: [Canvas]) throws -> String {
        let fonts = Fonts(home: home)
        let parts = ["v\(Renderer.version)", day.markdown(), label, String(data: try JSON.encoder.encode(canvases), encoding: .utf8)!,
                     FontAsset.all.filter(fonts.installed).map(\.file).joined(separator: ",")]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{1}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func renderFiles(_ key: String, canvases: [Canvas], directory: URL, prefix: String) throws -> (hash: String, files: [(Canvas, URL)]) {
        let day = try home.loadDay(key)
        let zh = try chinese(day)
        let label = try calendarist.label(for: key, chinese: zh)
        let hash = try fingerprint(day, label: label, canvases: canvases)
        let fonts = Fonts(home: home)
        if !fonts.missing.isEmpty { warnings.append("Handwriting fonts missing (\(fonts.missing.map(\.file).joined(separator: ", "))); using system fonts. Run `mura setup`.") }
        var renderer: Renderer?
        var files: [(Canvas, URL)] = []
        for canvas in canvases {
            let safeID = canvas.id.replacingOccurrences(of: "/", with: "_")
            let url = directory.appendingPathComponent("\(prefix)\(key)-\(safeID)-\(hash.prefix(12)).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                if renderer == nil { renderer = try Renderer(fonts: fonts) }
                try writePNG(try renderer!.render(day: day, label: label, chinese: zh, canvas: canvas), to: url)
            }
            files.append((canvas, url))
        }
        return (hash, files)
    }

    private func render(_ args: Args) throws -> [String: Any] {
        let key = try key(args)
        var canvases = desktop.canvases()
        if let size = args.values["--size"] {
            let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2, parts.allSatisfy({ (200...16384).contains($0) }) else { throw MuraError.usage("--size looks like 3840x2160") }
            canvases = [Canvas(id: "custom", width: parts[0], height: parts[1], safeTop: parts[1] / 40)]
        }
        guard !canvases.isEmpty else { throw MuraError.notFound("No display found; pass --size WxH") }
        let directory = args.values["--out"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? home.renders.appendingPathComponent("previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try renderFiles(key, canvases: canvases, directory: directory, prefix: "preview-")
        return ["date": key, "images": result.files.map { ["display": $0.0.id, "width": $0.0.width, "height": $0.0.height, "file": $0.1.path] }]
    }

    // MARK: wallpaper

    private func apply(_ key: String, onlyIfChanged: Bool) throws -> [String: Any] {
        let canvases = desktop.canvases()
        guard !canvases.isEmpty else { throw MuraError.notFound("No display found") }
        var state = try home.state()
        let result = try renderFiles(key, canvases: canvases, directory: home.renders, prefix: "")
        if onlyIfChanged, let last = state.history.last, last.day == key, last.hash == result.hash {
            return ["applied": false, "reason": "unchanged", "date": key]
        }
        let allSpaces = (try home.config().spaces ?? "all") == "all"
        var backup: URL?
        if allSpaces, let snapshot = desktop.storeSnapshot() {
            backup = home.backups.appendingPathComponent("store-\(Int(now.timeIntervalSince1970))-\(result.hash.prefix(8)).plist")
            try snapshot.write(to: backup!, options: .atomic)
        }
        var screens: [AppliedScreen] = []
        for (canvas, url) in result.files {
            let previous = desktop.current(canvas.id)
            if previous?.standardizedFileURL != url.standardizedFileURL { try desktop.set(url, on: canvas.id) }
            screens.append(AppliedScreen(id: canvas.id, image: url.path, previous: previous?.path))
        }
        if allSpaces {
            do { try desktop.spreadToAllSpaces(Dictionary(uniqueKeysWithValues: screens.map { ($0.id, URL(fileURLWithPath: $0.image)) })) } catch let error as MuraError { warnings.append(error.message) }
        }
        state.history.append(Applied(at: now, day: key, hash: result.hash, screens: screens, storeBackup: backup?.path))
        state.history = Array(state.history.suffix(30))
        try home.saveState(state)
        prune(state)
        return ["applied": true, "date": key, "images": screens.map { ["display": $0.id, "file": $0.image] }]
    }

    private func tick() throws -> [String: Any] {
        let log = home.logs.appendingPathComponent("tick.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: log.path))?[.size] as? Int, size > 512_000 {
            try? Data().write(to: log)
        }
        return try home.withLock { try apply(try calendarist.today, onlyIfChanged: true) }
    }

    private func undo() throws -> [String: Any] {
        var state = try home.state()
        guard let last = state.history.popLast() else { throw MuraError.notFound("Nothing to undo") }
        if let backup = last.storeBackup, let data = try? Data(contentsOf: URL(fileURLWithPath: backup)) {
            try desktop.restoreStore(data)
            try home.saveState(state)
            prune(state)
            return ["restored": last.screens.map { ["display": $0.id, "file": $0.previous ?? NSNull()] as [String: Any] }, "undid": last.day, "allSpaces": true]
        }
        var restored: [[String: Any]] = []
        for screen in last.screens {
            guard let previous = screen.previous else { continue }
            guard FileManager.default.fileExists(atPath: previous) else {
                warnings.append("Previous wallpaper \(previous) is gone; display \(screen.id) left as is.")
                continue
            }
            try desktop.set(URL(fileURLWithPath: previous), on: screen.id)
            restored.append(["display": screen.id, "file": previous])
        }
        try home.saveState(state)
        return ["restored": restored, "undid": last.day]
    }

    /// Keeps every render still referenced by history (so undo works) and drops the rest.
    private func prune(_ state: State) {
        let keep = Set(state.history.flatMap { $0.screens.flatMap { [$0.image, $0.previous].compactMap { $0 } } }
            .map { URL(fileURLWithPath: $0).lastPathComponent })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.renders.path)) ?? []
        for name in names where name.hasSuffix(".png") && !keep.contains(name) {
            try? FileManager.default.removeItem(at: home.renders.appendingPathComponent(name))
        }
        let backups = Set(state.history.compactMap { $0.storeBackup.map { URL(fileURLWithPath: $0).lastPathComponent } })
        for name in (try? FileManager.default.contentsOfDirectory(atPath: home.backups.path)) ?? [] where !backups.contains(name) {
            try? FileManager.default.removeItem(at: home.backups.appendingPathComponent(name))
        }
    }

    // MARK: setup

    private func setup(_ args: Args) throws -> [String: Any] {
        let fetched = try Fonts(home: home).install()
        var out: [String: Any] = ["home": home.root.path, "fontsDownloaded": fetched]
        if !args.set.contains("--no-schedule") { out["schedule"] = try Schedule(home: home, env: env).install() }
        return out
    }

    private func schedule(_ args: Args) throws -> [String: Any] {
        let schedule = Schedule(home: home, env: env)
        switch args.positional.first ?? "status" {
        case "install": return try schedule.install()
        case "uninstall": return schedule.uninstall()
        case "status": return schedule.status()
        default: throw MuraError.usage("mura schedule install|uninstall|status")
        }
    }

    private func config(_ args: Args) throws -> [String: Any] {
        var config = try home.config()
        let p = args.positional
        if p.first == "set" || p.first == "unset" {
            guard p.count == (p[0] == "set" ? 3 : 2) else { throw MuraError.usage("mura config set KEY VALUE | mura config unset KEY") }
            let value = p[0] == "set" ? p[2] : nil
            switch p[1] {
            case "timezone":
                if let value, TimeZone(identifier: value) == nil { throw MuraError.usage("Unknown timezone '\(value)', e.g. Asia/Shanghai") }
                config.timezone = value
            case "lang":
                if let value, !["zh", "en", "auto"].contains(value) { throw MuraError.usage("lang is zh, en or auto") }
                config.lang = value
            case "spaces":
                if let value, !["all", "current"].contains(value) { throw MuraError.usage("spaces is all or current") }
                config.spaces = value
            default: throw MuraError.usage("Config keys: timezone, lang, spaces")
            }
            try home.withLock { try home.saveConfig(config) }
        } else if !p.isEmpty {
            throw MuraError.usage("mura config [set KEY VALUE | unset KEY]")
        }
        let cal = try calendarist
        return ["timezone": cal.timeZone.identifier, "lang": config.lang ?? "auto", "spaces": config.spaces ?? "all", "today": cal.today, "file": home.configURL.path]
    }

    private func doctor() throws -> [String: Any] {
        let fonts = Fonts(home: home)
        let state = try home.state()
        let renders = Set(state.history.flatMap { $0.screens.map { URL(fileURLWithPath: $0.image).lastPathComponent } })
        let cal = try calendarist
        return [
            "home": home.root.path,
            "executable": Schedule.executable,
            "today": cal.today,
            "timezone": cal.timeZone.identifier,
            "fonts": FontAsset.all.map { ["file": $0.file, "installed": fonts.installed($0), "license": $0.license] },
            "schedule": Schedule(home: home, env: env).status(),
            "displays": desktop.canvases().map { canvas -> [String: Any] in
                let current = desktop.current(canvas.id)?.path
                return ["id": canvas.id, "width": canvas.width, "height": canvas.height,
                        "wallpaper": current ?? NSNull(), "showingMura": current.map { renders.contains(URL(fileURLWithPath: $0).lastPathComponent) } ?? false]
            },
            "lastApplied": state.history.last.map { ["day": $0.day, "at": ISO8601DateFormatter().string(from: $0.at)] } ?? NSNull(),
        ]
    }

    static let help: [String: Any] = [
        "about": "Mura puts a day's list on the macOS wallpaper in an Excalidraw-style hand-drawn look. Days are Markdown files; today's changes apply at once, other days switch in automatically at midnight (after `mura setup`).",
        "dates": "--date today|tomorrow|yesterday|+N|-N|YYYY-MM-DD (default today, in the configured timezone)",
        "commands": [
            "mura show [--date D]": "the day's title, note and numbered items",
            "mura list": "days that have a file",
            "mura plan [--date D] [--title T] [--note N] (ITEM… | --stdin | --file F)": "replace the day. Markdown: '# title', '- [ ] item', '- [x] done', '! ' prefix = important, '> note'",
            "mura add ITEM… [--important] [--date D]": "append items",
            "mura done N… / undone N… / rm N… [--date D]": "check, uncheck or delete items by number",
            "mura title TEXT | --clear, mura note TEXT | --clear, mura clear [--date D]": "edit the title, the note, or empty the day",
            "mura render [--date D] [--size WxH] [--out DIR]": "PNG previews per display without touching the wallpaper",
            "mura apply [--date D]": "render and set as wallpaper on every display",
            "mura undo": "put back the wallpaper from before the last apply",
            "mura setup [--no-schedule]": "download the handwriting fonts and install the midnight switch",
            "mura schedule install|uninstall|status": "manage the LaunchAgent that runs `mura tick`",
            "mura config [set KEY VALUE | unset KEY]": "keys: timezone (e.g. Asia/Shanghai), lang (zh|en|auto), spaces (all|current: whether every desktop Space gets the wallpaper)",
            "mura doctor": "fonts, schedule, displays and what is on screen",
        ],
        "flags": ["--no-apply": "edit today without touching the wallpaper"],
        "output": "One JSON object on stdout: {ok, command, data | error{code,message}, warnings?}. Exit 0 ok, 1 failure, 2 usage.",
    ]
}
