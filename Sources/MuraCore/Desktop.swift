import AppKit
import Foundation

/// The only place Mura touches the real desktop; tests swap in a fake.
public protocol Desktop {
    func canvases() -> [Canvas]
    func current(_ id: String) -> URL?
    func set(_ url: URL, on id: String) throws
    /// macOS only changes the current Space; these copy that choice to every Space and can roll it back.
    func storeSnapshot() -> Data?
    func spreadToAllSpaces(_ images: [String: URL]) throws
    func restoreStore(_ data: Data) throws
}

public struct MacDesktop: Desktop {
    public init() {}

    private func screens() -> [(String, NSScreen)] {
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return (number?.stringValue ?? screen.localizedName, screen)
        }
    }

    public func canvases() -> [Canvas] {
        screens().map { id, screen in
            let scale = screen.backingScaleFactor
            let frame = screen.frame, visible = screen.visibleFrame
            return Canvas(id: id,
                          width: Int((frame.width * scale).rounded()),
                          height: Int((frame.height * scale).rounded()),
                          safeTop: Int(((frame.maxY - visible.maxY) * scale).rounded()),
                          safeBottom: Int(((visible.minY - frame.minY) * scale).rounded()))
        }
    }

    public func current(_ id: String) -> URL? {
        screens().first { $0.0 == id }.flatMap { NSWorkspace.shared.desktopImageURL(for: $0.1) }
    }

    public func set(_ url: URL, on id: String) throws {
        guard let screen = screens().first(where: { $0.0 == id })?.1 else {
            throw MuraError.notFound("Display \(id) is no longer connected")
        }
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
                .fillColor: NSColor(cgColor: Ink.paper) ?? .white,
            ])
        } catch {
            throw MuraError.failed("macOS refused the wallpaper: \(error.localizedDescription)", code: "wallpaper")
        }
    }

    // The wallpaper store is private and undocumented (macOS 14+). Every edit keeps a backup for undo,
    // and anything unexpected leaves the store untouched.
    static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    public func storeSnapshot() -> Data? { try? Data(contentsOf: MacDesktop.store) }

    public func spreadToAllSpaces(_ images: [String: URL]) throws {
        // Let WallpaperAgent finish recording the official change first, so it cannot overwrite our edit.
        for _ in 0..<30 where !storeNames(images) { usleep(100_000) }
        guard let before = storeSnapshot(),
              var root = try? PropertyListSerialization.propertyList(from: before, options: .mutableContainersAndLeaves, format: nil) as? [String: Any],
              var displays = root["Displays"] as? [String: Any],
              var spaces = root["Spaces"] as? [String: Any],
              let template = imageDesktopTemplate(displays: displays, spaces: spaces)
        else { throw MuraError.failed("Unrecognised wallpaper store; only the current Space was changed", code: "spaces") }

        for (id, url) in images {
            guard let number = UInt32(id), let cfUUID = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { continue }
            let uuid = CFUUIDCreateString(nil, cfUUID) as String
            let desktop = try imageDesktop(url, template: template)
            guard let display = withDesktop(displays[uuid], desktop) else { continue }
            displays[uuid] = display
            for (spaceID, value) in spaces {
                guard var space = value as? [String: Any], var perDisplay = space["Displays"] as? [String: Any],
                      perDisplay[uuid] != nil else { continue }
                perDisplay[uuid] = withDesktop(perDisplay[uuid], desktop) ?? display
                space["Displays"] = perDisplay
                spaces[spaceID] = space
            }
        }
        root["Displays"] = displays
        root["Spaces"] = spaces
        try writeStore(try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0))

        // WallpaperAgent silently resets a store it cannot decode. Detect that and put the old one back.
        usleep(1_500_000)
        let spaceCount = { (data: Data?) -> Int in
            guard let data, let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return -1 }
            return (plist["Spaces"] as? [String: Any])?.count ?? -1
        }
        if spaceCount(storeSnapshot()) < spaceCount(before) || !storeNames(images) {
            try writeStore(before)
            throw MuraError.failed("macOS rejected the all-Spaces update; restored its wallpaper settings, so only the current Space shows Mura", code: "spaces")
        }
    }

    /// Entries are either "individual" {Desktop, Idle} or "linked" {Linked}: one choice for both desktop and
    /// screen saver. A linked entry keeps its choice as the screen saver and gets our image as the desktop.
    private func withDesktop(_ value: Any?, _ desktop: [String: Any]) -> [String: Any]? {
        guard var entry = value as? [String: Any] else { return nil }
        switch entry["Type"] as? String {
        case "individual" where entry["Idle"] != nil:
            entry["Desktop"] = desktop
            return entry
        case "linked":
            guard let linked = entry["Linked"] as? [String: Any] else { return nil }
            return ["Type": "individual", "Desktop": desktop, "Idle": linked]
        default:
            return nil
        }
    }

    private func storeNames(_ images: [String: URL]) -> Bool {
        guard let data = storeSnapshot() else { return false }
        return images.values.allSatisfy { data.range(of: Data($0.lastPathComponent.utf8)) != nil }
    }

    /// Any existing plain-image choice; it carries the option blobs we do not interpret.
    private func imageDesktopTemplate(displays: [String: Any], spaces: [String: Any]) -> [String: Any]? {
        let nested = spaces.values.flatMap { (($0 as? [String: Any])?["Displays"] as? [String: Any]).map { Array($0.values) } ?? [] }
        for entry in Array(displays.values) + nested {
            guard let desktop = (entry as? [String: Any])?["Desktop"] as? [String: Any],
                  let content = desktop["Content"] as? [String: Any],
                  let choice = (content["Choices"] as? [Any])?.first as? [String: Any],
                  choice["Provider"] as? String == "com.apple.wallpaper.choice.image" else { continue }
            return desktop
        }
        return nil
    }

    private func imageDesktop(_ url: URL, template: [String: Any]) throws -> [String: Any] {
        let configuration = try PropertyListSerialization.data(fromPropertyList: [
            "type": "imageFile", "url": ["relative": url.absoluteString],
        ], format: .binary, options: 0)
        var desktop = template
        var content = template["Content"] as? [String: Any] ?? [:]
        content["Choices"] = [["Provider": "com.apple.wallpaper.choice.image", "Files": [Any](), "Configuration": configuration]]
        desktop["Content"] = content
        desktop["LastSet"] = Date()
        desktop["LastUse"] = Date()
        return desktop
    }

    public func restoreStore(_ data: Data) throws { try writeStore(data) }

    private func writeStore(_ data: Data) throws {
        try data.write(to: MacDesktop.store, options: .atomic)
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["WallpaperAgent"]
        kill.standardError = FileHandle.nullDevice
        try kill.run()
        kill.waitUntilExit()
    }
}
