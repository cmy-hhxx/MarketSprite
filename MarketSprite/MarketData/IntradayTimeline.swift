import Foundation

enum IntradayTimeline {
    static func progress(at date: Date, market: Market) -> Double? {
        let minute = minuteOfDay(for: date, market: market)
        let sessions = sessions(for: market)
        let totalDuration = sessions.reduce(0.0) { total, session in
            total + session.end - session.start
        }
        var elapsed = 0.0

        for session in sessions {
            if minute < session.start {
                return nil
            }
            if minute <= session.end {
                return (elapsed + minute - session.start) / totalDuration
            }
            elapsed += session.end - session.start
        }

        return nil
    }

    private static func minuteOfDay(for date: Date, market: Market) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
    }

    private static func sessions(for market: Market) -> [Session] {
        switch market {
        case .aShare:
            [
                Session(start: 9 * 60 + 30, end: 11 * 60 + 30),
                Session(start: 13 * 60, end: 15 * 60),
            ]
        case .hongKong:
            [
                Session(start: 9 * 60 + 30, end: 12 * 60),
                Session(start: 13 * 60, end: 16 * 60),
            ]
        case .unitedStates:
            [Session(start: 9 * 60 + 30, end: 16 * 60)]
        }
    }

    private struct Session {
        let start: Double
        let end: Double
    }
}
