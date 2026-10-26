import Foundation

/// A per-user LaunchAgent that runs `mura tick` every few minutes and at login. Nothing stays resident.
struct Schedule {
    static let label = "io.github.risingjerry.mura"
    static let interval = 300

    let home: Home
    let env: [String: String]

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Schedule.label).plist")
    }

    var domain: String { "gui/\(getuid())" }

    static var executable: String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    var installed: Bool { FileManager.default.fileExists(atPath: plistURL.path) }
    var loaded: Bool { launchctl(["print", "\(domain)/\(Schedule.label)"]) == 0 }

    func install() throws -> [String: Any] {
        try home.ensure()
        var plist: [String: Any] = [
            "Label": Schedule.label,
            "ProgramArguments": [Schedule.executable, "tick"],
            "StartInterval": Schedule.interval,
            "RunAtLoad": true,
            "ProcessType": "Background",
            "StandardOutPath": home.logs.appendingPathComponent("tick.log").path,
            "StandardErrorPath": home.logs.appendingPathComponent("tick.log").path,
        ]
        if let custom = env["MURA_HOME"], !custom.isEmpty {
            plist["EnvironmentVariables"] = ["MURA_HOME": home.root.path]
        }
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL, options: .atomic)
        _ = launchctl(["bootout", "\(domain)/\(Schedule.label)"])
        guard launchctl(["bootstrap", domain, plistURL.path]) == 0 else {
            throw MuraError.failed("launchctl bootstrap failed for \(plistURL.path)", code: "schedule")
        }
        return status()
    }

    func uninstall() -> [String: Any] {
        _ = launchctl(["bootout", "\(domain)/\(Schedule.label)"])
        try? FileManager.default.removeItem(at: plistURL)
        return status()
    }

    func status() -> [String: Any] {
        var out: [String: Any] = ["installed": installed, "loaded": installed && loaded, "plist": plistURL.path,
                                  "everySeconds": Schedule.interval]
        if let plist = NSDictionary(contentsOf: plistURL), let args = plist["ProgramArguments"] as? [String], let exe = args.first {
            out["executable"] = exe
            if !FileManager.default.isExecutableFile(atPath: exe) { out["warning"] = "Scheduled binary \(exe) no longer exists; run `mura schedule install` again." }
        }
        return out
    }

    private func launchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
