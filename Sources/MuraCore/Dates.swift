import Foundation

public struct Calendarist {
    public let timeZone: TimeZone
    public let now: Date

    public init(timeZone: TimeZone, now: Date = Date()) {
        self.timeZone = timeZone
        self.now = now
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public var today: String { key(for: now) }

    /// Accepts today/tomorrow/yesterday (and 今天/明天/昨天/后天), +N/-N days, or YYYY-MM-DD.
    public func resolve(_ spec: String?) throws -> String {
        let spec = (spec ?? "today").trimmingCharacters(in: .whitespaces).lowercased()
        let offsets = ["today": 0, "tomorrow": 1, "yesterday": -1, "今天": 0, "明天": 1, "昨天": -1, "后天": 2]
        if let offset = offsets[spec] { return key(offsetDays: offset) }
        if let first = spec.first, first == "+" || first == "-", let offset = Int(spec) { return key(offsetDays: offset) }
        if let date = parse(spec) { return key(for: date) }
        throw MuraError.usage("Unknown date '\(spec)'. Use today, tomorrow, yesterday, +N, -N or YYYY-MM-DD.")
    }

    func key(offsetDays: Int) -> String {
        key(for: calendar.date(byAdding: .day, value: offsetDays, to: now)!)
    }

    func key(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func parse(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, key.count == 10 else { return nil }
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        return date.flatMap { self.key(for: $0) == key ? $0 : nil }
    }

    public func label(for key: String, chinese: Bool) -> String {
        guard let date = parse(key) else { return key }
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        if chinese {
            let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return "\(c.month!)月\(c.day!)日 \(weekdays[c.weekday! - 1])"
        }
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(weekdays[c.weekday! - 1]) · \(months[c.month! - 1]) \(c.day!)"
    }
}
