import XCTest
@testable import MarketSprite

final class TradingCalendarTests: XCTestCase {
    func testSessionDateUsesTheInstrumentMarketTimeZone() throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-30T16:30:00Z")
        )

        XCTAssertEqual(
            TradingCalendar.sessionDate(for: instant, market: .aShare),
            "2026-07-31"
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: instant, market: .hongKong),
            "2026-07-31"
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: instant, market: .unitedStates),
            "2026-07-30"
        )
    }

    func testAShareExtremaAppearOnlyBetweenTheLatestCloseAndNextOpen() throws {
        let formatter = ISO8601DateFormatter()
        let afterClose = try XCTUnwrap(formatter.date(from: "2026-07-30T07:30:00Z"))
        let beforeNextOpen = try XCTUnwrap(formatter.date(from: "2026-07-31T01:15:00Z"))
        let afterNextOpen = try XCTUnwrap(formatter.date(from: "2026-07-31T01:31:00Z"))

        XCTAssertTrue(TradingCalendar.shouldShowAShareExtrema(now: afterClose))
        XCTAssertTrue(TradingCalendar.shouldShowAShareExtrema(now: beforeNextOpen))
        XCTAssertFalse(TradingCalendar.shouldShowAShareExtrema(now: afterNextOpen))
    }
}
