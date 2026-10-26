import AppKit
import Foundation
import XCTest
@testable import MuraCore

final class FakeDesktop: Desktop {
    var screens = [Canvas(id: "1", width: 1600, height: 1000, safeTop: 50, safeBottom: 0)]
    var wallpapers: [String: URL] = ["1": URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")]

    func canvases() -> [Canvas] { screens }
    func current(_ id: String) -> URL? { wallpapers[id] }
    func set(_ url: URL, on id: String) throws { wallpapers[id] = url }

    /// Models the macOS store as a snapshot of every display's wallpaper.
    var spread = 0
    func storeSnapshot() -> Data? { try? JSONEncoder().encode(wallpapers) }
    func spreadToAllSpaces(_ images: [String: URL]) throws { spread += 1 }
    func restoreStore(_ data: Data) throws { wallpapers = try JSONDecoder().decode([String: URL].self, from: data) }
}

final class DayTests: XCTestCase {
    func testParsesMarkdownAndPlainLines() {
        let day = Day.parse("""
        # 周二
        - [ ] ! 交房租
        - [x] Call mom
        1. numbered
        plain line
        > first
        > second
        """)
        XCTAssertEqual(day.title, "周二")
        XCTAssertEqual(day.items, [
            Item(text: "交房租", important: true),
            Item(text: "Call mom", done: true),
            Item(text: "numbered"),
            Item(text: "plain line"),
        ])
        XCTAssertEqual(day.note, "first\nsecond")
        XCTAssertEqual(Day.parse(day.markdown()), day)
    }

    func testDatesFollowConfiguredZone() throws {
        // 2026-10-26 20:00 in New York is already 10-27 in Shanghai.
        let now = ISO8601DateFormatter().date(from: "2026-10-27T00:00:00Z")!
        let shanghai = Calendarist(timeZone: TimeZone(identifier: "Asia/Shanghai")!, now: now)
        let newYork = Calendarist(timeZone: TimeZone(identifier: "America/New_York")!, now: now)
        XCTAssertEqual(shanghai.today, "2026-10-27")
        XCTAssertEqual(newYork.today, "2026-10-26")
        XCTAssertEqual(try shanghai.resolve("tomorrow"), "2026-10-28")
        XCTAssertEqual(try shanghai.resolve("明天"), "2026-10-28")
        XCTAssertEqual(try shanghai.resolve("-1"), "2026-10-26")
        XCTAssertEqual(try shanghai.resolve("2026-12-31"), "2026-12-31")
        XCTAssertThrowsError(try shanghai.resolve("2026-02-30"))
        XCTAssertEqual(shanghai.label(for: "2026-10-27", chinese: true), "10月27日 周二")
        XCTAssertEqual(shanghai.label(for: "2026-10-27", chinese: false), "Tue · Oct 27")
    }
}

final class CommandTests: XCTestCase {
    var root: URL!
    var desktop: FakeDesktop!
    let now = ISO8601DateFormatter().date(from: "2026-10-27T02:00:00Z")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mura-tests-\(UUID().uuidString)")
        desktop = FakeDesktop()
        _ = run("config", "set", "timezone", "Asia/Shanghai")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func run(_ argv: String..., stdin: String = "") -> [String: Any] {
        let mura = Mura(home: Home(root: root), desktop: desktop, env: ["MURA_HOME": root.path], now: now)
        let output = mura.run(argv) { stdin }
        return try! JSONSerialization.jsonObject(with: Data(output.json.utf8)) as! [String: Any]
    }

    func data(_ result: [String: Any]) -> [String: Any] { result["data"] as! [String: Any] }

    func testPlanningTomorrowLeavesWallpaperAlone() {
        let result = run("plan", "--date", "tomorrow", "--stdin", stdin: "- [ ] write\n- [ ] ship\n")
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(data(result)["date"] as? String, "2026-10-28")
        XCTAssertEqual((data(result)["wallpaper"] as? [String: Any])?["applied"] as? Bool, false)
        XCTAssertEqual(desktop.wallpapers["1"]?.lastPathComponent, "DefaultDesktop.heic")
    }

    func testEditingTodayAppliesAndUndoRestores() throws {
        let added = run("add", "交房租", "--important")
        XCTAssertEqual((data(added)["wallpaper"] as? [String: Any])?["applied"] as? Bool, true)
        let applied = try XCTUnwrap(desktop.wallpapers["1"])
        XCTAssertTrue(applied.path.hasPrefix(root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: applied.path))

        run("done", "1")
        XCTAssertNotEqual(desktop.wallpapers["1"], applied, "a changed day gets a new file name so macOS refreshes it")

        run("undo")
        XCTAssertEqual(desktop.wallpapers["1"], applied)
        run("undo")
        XCTAssertEqual(desktop.wallpapers["1"]?.lastPathComponent, "DefaultDesktop.heic")
        XCTAssertEqual(run("undo")["ok"] as? Bool, false)
    }

    func testTickOnlyAppliesWhenSomethingChanged() {
        run("plan", "a", "b")
        XCTAssertEqual(data(run("tick"))["reason"] as? String, "unchanged")

        desktop.wallpapers["1"] = URL(fileURLWithPath: "/tmp/user-picked.png")
        XCTAssertEqual(data(run("tick"))["applied"] as? Bool, false, "tick must not fight a wallpaper the user picked")

        desktop.screens.append(Canvas(id: "2", width: 1200, height: 800))
        XCTAssertEqual(data(run("tick"))["applied"] as? Bool, true, "a new display gets its own render")
        XCTAssertNotNil(desktop.wallpapers["2"])
    }

    func testRenderFitsCrowdedDays() throws {
        let many = (1...40).map { "- [ ] item \($0) with a fairly long description that has to wrap onto another line" }.joined(separator: "\n")
        run("plan", "--date", "+1", "--stdin", stdin: many + "\n> note")
        let images = try XCTUnwrap(data(run("render", "--date", "+1", "--size", "1280x800", "--out", root.appendingPathComponent("out").path))["images"] as? [[String: Any]])
        let file = try XCTUnwrap(images.first?["file"] as? String)
        let image = try XCTUnwrap(NSImage(contentsOfFile: file))
        XCTAssertEqual(image.representations.first?.pixelsWide, 1280)
    }

    func testUsageErrors() {
        let bad = run("done", "9")
        XCTAssertEqual(bad["ok"] as? Bool, false)
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "usage")
        XCTAssertEqual(run("frobnicate")["ok"] as? Bool, false)
        XCTAssertEqual(run("add", "x", "--bogus")["ok"] as? Bool, false)
    }
}
