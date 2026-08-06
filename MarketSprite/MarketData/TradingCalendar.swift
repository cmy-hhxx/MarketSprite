import Foundation

enum TradingCalendar {
    /// Non-weekend A-share holidays for 2026 (SSE/SZSE/BSE announcements).
    private static let aShareHolidays2026: Set<String> = [
        "2026-01-01", "2026-01-02",
        "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19",
        "2026-02-20", "2026-02-23",
        "2026-04-06",
        "2026-05-01", "2026-05-04", "2026-05-05",
        "2026-06-19",
        "2026-09-25",
        "2026-10-01", "2026-10-02", "2026-10-05", "2026-10-06", "2026-10-07",
    ]

    static func sessionDate(for date: Date, market: Market) -> String {
        let components = calendar(for: market).dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func shouldShowAShareExtrema(now: Date = Date()) -> Bool {
        let market = Market.aShare
        let calendar = calendar(for: market)
        let dayStart = calendar.startOfDay(for: now)
        let lastClosedDay: Date

        if isAShareTradingDay(dayStart) {
            guard let close = calendar.date(
                bySettingHour: 15,
                minute: 0,
                second: 0,
                of: dayStart
            ) else { return false }
            if now >= close {
                lastClosedDay = dayStart
            } else if let previous = previousAShareTradingDay(before: dayStart) {
                lastClosedDay = previous
            } else {
                return false
            }
        } else if let previous = previousAShareTradingDay(before: dayStart) {
            lastClosedDay = previous
        } else {
            return false
        }

        guard
            let sessionClose = calendar.date(
                bySettingHour: 15,
                minute: 0,
                second: 0,
                of: lastClosedDay
            ),
            let nextDay = nextAShareTradingDay(after: lastClosedDay),
            let nextOpen = calendar.date(
                bySettingHour: 9,
                minute: 30,
                second: 0,
                of: nextDay
            )
        else { return false }

        return now >= sessionClose && now < nextOpen
    }

    private static func calendar(for market: Market) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar
    }

    private static func isAShareTradingDay(_ date: Date) -> Bool {
        let calendar = calendar(for: .aShare)
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        return !aShareHolidays2026.contains(sessionDate(for: date, market: .aShare))
    }

    private static func previousAShareTradingDay(before date: Date) -> Date? {
        let calendar = calendar(for: .aShare)
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<20 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return nil
            }
            cursor = previous
            if isAShareTradingDay(cursor) { return cursor }
        }
        return nil
    }

    private static func nextAShareTradingDay(after date: Date) -> Date? {
        let calendar = calendar(for: .aShare)
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<20 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                return nil
            }
            cursor = next
            if isAShareTradingDay(cursor) { return cursor }
        }
        return nil
    }
}
