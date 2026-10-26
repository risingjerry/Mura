import Foundation

public struct Item: Codable, Equatable {
    public var text: String
    public var done: Bool
    public var important: Bool

    public init(text: String, done: Bool = false, important: Bool = false) {
        self.text = text
        self.done = done
        self.important = important
    }
}

/// One day on the wall. Stored as a small Markdown file so agents and people can both edit it:
///
///     # Optional title
///     - [ ] ! important item
///     - [x] finished item
///     > a note shown at the bottom
public struct Day: Codable, Equatable {
    public var title: String?
    public var items: [Item]
    public var note: String?

    public init(title: String? = nil, items: [Item] = [], note: String? = nil) {
        self.title = title
        self.items = items
        self.note = note
    }

    public var isEmpty: Bool { title == nil && items.isEmpty && note == nil }

    public static func parse(_ text: String) -> Day {
        var day = Day()
        var noteLines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if day.title == nil, !title.isEmpty { day.title = title }
                continue
            }
            if line.hasPrefix(">") {
                noteLines.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            if let item = parseItem(line) { day.items.append(item) }
        }
        let note = noteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        day.note = note.isEmpty ? nil : note
        return day
    }

    static func parseItem(_ line: String) -> Item? {
        var rest = Substring(line)
        var done = false
        if let marker = ["- ", "* ", "+ "].first(where: { rest.hasPrefix($0) }) {
            rest = rest.dropFirst(marker.count)
        } else if let dot = rest.firstIndex(where: { $0 == "." || $0 == ")" || $0 == "、" }),
                  dot > rest.startIndex, rest[..<dot].allSatisfy(\.isNumber) {
            rest = rest[rest.index(after: dot)...]
        }
        rest = rest.drop { $0 == " " }
        for (box, isDone) in [("[ ]", false), ("[x]", true), ("[X]", true)] where rest.hasPrefix(box) {
            done = isDone
            rest = rest.dropFirst(box.count).drop { $0 == " " }
        }
        var important = false
        if rest.hasPrefix("!") || rest.hasPrefix("！") {
            important = true
            rest = rest.dropFirst().drop { $0 == " " }
        }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Item(text: text, done: done, important: important)
    }

    public func markdown() -> String {
        var out: [String] = []
        if let title { out += ["# \(title)", ""] }
        for item in items {
            out.append("- [\(item.done ? "x" : " ")] \(item.important ? "! " : "")\(item.text)")
        }
        if let note {
            if !out.isEmpty { out.append("") }
            out += note.components(separatedBy: "\n").map { "> \($0)" }
        }
        return out.joined(separator: "\n") + "\n"
    }

    var containsCJK: Bool {
        let all = ([title, note].compactMap { $0 } + items.map(\.text)).joined()
        return all.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }
    }
}
