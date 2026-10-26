import Foundation

public enum MuraError: Error {
    case usage(String)
    case notFound(String)
    case failed(String, code: String)

    var code: String {
        switch self {
        case .usage: return "usage"
        case .notFound: return "not_found"
        case .failed(_, let code): return code
        }
    }

    var message: String {
        switch self {
        case .usage(let m), .notFound(let m), .failed(let m, _): return m
        }
    }
}

public struct Config: Codable, Equatable {
    /// IANA zone that decides what "today" is, e.g. Asia/Shanghai. Defaults to the system zone.
    public var timezone: String?
    /// zh, en or auto (auto: Chinese labels when the day contains Chinese text).
    public var lang: String?
    /// all (default): every Space shows the wallpaper; current: only what macOS changes by itself.
    public var spaces: String?

    public init(timezone: String? = nil, lang: String? = nil, spaces: String? = nil) {
        self.timezone = timezone
        self.lang = lang
        self.spaces = spaces
    }
}

public struct Applied: Codable, Equatable {
    public var at: Date
    public var day: String
    public var hash: String
    public var screens: [AppliedScreen]
    /// Copy of the macOS wallpaper store taken just before this apply (all-Spaces mode).
    public var storeBackup: String?
}

public struct AppliedScreen: Codable, Equatable {
    public var id: String
    public var image: String
    public var previous: String?
}

public struct State: Codable, Equatable {
    public var history: [Applied] = []
}

/// Everything Mura owns lives under one directory (default ~/Library/Application Support/Mura).
public struct Home {
    public let root: URL
    let fm = FileManager.default

    public init(root: URL) { self.root = root }

    public static func resolve(env: [String: String]) -> Home {
        if let path = env["MURA_HOME"], !path.isEmpty {
            return Home(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Home(root: support.appendingPathComponent("Mura"))
    }

    var days: URL { root.appendingPathComponent("days") }
    var renders: URL { root.appendingPathComponent("renders") }
    var fonts: URL { root.appendingPathComponent("fonts") }
    var logs: URL { root.appendingPathComponent("logs") }
    var backups: URL { root.appendingPathComponent("backups") }
    var configURL: URL { root.appendingPathComponent("config.json") }
    var stateURL: URL { root.appendingPathComponent("state.json") }

    func ensure() throws {
        for dir in [days, renders, fonts, logs, backups] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func dayURL(_ key: String) -> URL { days.appendingPathComponent("\(key).md") }

    public func loadDay(_ key: String) throws -> Day {
        let url = dayURL(key)
        guard fm.fileExists(atPath: url.path) else { return Day() }
        return Day.parse(try String(contentsOf: url, encoding: .utf8))
    }

    public func saveDay(_ day: Day, key: String) throws {
        try ensure()
        if day.isEmpty {
            try? fm.removeItem(at: dayURL(key))
        } else {
            try day.markdown().write(to: dayURL(key), atomically: true, encoding: .utf8)
        }
    }

    func dayKeys() -> [String] {
        ((try? fm.contentsOfDirectory(atPath: days.path)) ?? [])
            .filter { $0.hasSuffix(".md") }
            .map { String($0.dropLast(3)) }
            .sorted()
    }

    func load<T: Decodable>(_ type: T.Type, from url: URL, default value: T) throws -> T {
        guard let data = try? Data(contentsOf: url) else { return value }
        do { return try JSON.decoder.decode(T.self, from: data) } catch {
            throw MuraError.failed("\(url.lastPathComponent) is not valid JSON: \(error.localizedDescription)", code: "corrupt")
        }
    }

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        try ensure()
        try JSON.encoder.encode(value).write(to: url, options: .atomic)
    }

    public func config() throws -> Config { try load(Config.self, from: configURL, default: Config()) }
    public func state() throws -> State { try load(State.self, from: stateURL, default: State()) }
    func saveConfig(_ config: Config) throws { try save(config, to: configURL) }
    func saveState(_ state: State) throws { try save(state, to: stateURL) }

    /// Serialises writers (an agent and the scheduled tick may run at the same time).
    func withLock<T>(_ body: () throws -> T) throws -> T {
        try ensure()
        let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw MuraError.failed("Cannot open lock file in \(root.path)", code: "io") }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
