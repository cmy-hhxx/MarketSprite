import Foundation

/// A-share session helpers: 2026 holidays + BS marker visibility window.
enum AShareCalendar {
    private static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    /// Non-weekend A-share holidays for 2026 (SSE/SZSE/BSE announcements).
    private static let holidays2026: Set<String> = [
        // 元旦
        "2026-01-01", "2026-01-02",
        // 春节
        "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19",
        "2026-02-20", "2026-02-23",
        // 清明
        "2026-04-06",
        // 劳动节
        "2026-05-01", "2026-05-04", "2026-05-05",
        // 端午
        "2026-06-19",
        // 中秋
        "2026-09-25",
        // 国庆
        "2026-10-01", "2026-10-02", "2026-10-05", "2026-10-06", "2026-10-07"
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghaiTimeZone
        return calendar
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = shanghaiTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func isTradingDay(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        return !holidays2026.contains(dayKey(date))
    }

    static func previousTradingDay(before date: Date) -> Date? {
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<20 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            cursor = previous
            if isTradingDay(cursor) { return cursor }
        }
        return nil
    }

    static func nextTradingDay(after date: Date) -> Date? {
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<20 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
            if isTradingDay(cursor) { return cursor }
        }
        return nil
    }

    /// Show B/S from session close 15:00 until next trading day 09:30 (Asia/Shanghai).
    static func shouldShowBSMarkers(now: Date = Date()) -> Bool {
        let dayStart = calendar.startOfDay(for: now)
        let lastClosedDay: Date
        if isTradingDay(dayStart) {
            guard let close = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: dayStart) else {
                return false
            }
            if now >= close {
                lastClosedDay = dayStart
            } else if let previous = previousTradingDay(before: dayStart) {
                lastClosedDay = previous
            } else {
                return false
            }
        } else if let previous = previousTradingDay(before: dayStart) {
            lastClosedDay = previous
        } else {
            return false
        }

        guard
            let sessionClose = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: lastClosedDay),
            let nextDay = nextTradingDay(after: lastClosedDay),
            let nextOpen = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: nextDay)
        else {
            return false
        }
        return now >= sessionClose && now < nextOpen
    }
}
