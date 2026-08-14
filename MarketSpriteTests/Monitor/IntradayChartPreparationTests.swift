import XCTest
@testable import MarketSprite

final class IntradayChartPreparationTests: XCTestCase {
    func testBuildsTimelineRangeAndExtremaInOnePreparedValue() throws {
        let preparation = IntradayChartPreparation(
            points: [
                bar(hour: 9, minute: 30, close: 10),
                bar(hour: 10, minute: 0, close: 7),
                bar(hour: 10, minute: 30, close: 8),
                bar(hour: 12, minute: 0, close: 6),
            ],
            market: .aShare,
            dayOpen: 9,
            previousClose: 8,
            showBSMarkers: true
        )

        XCTAssertEqual(preparation.points.map(\.close), [10, 7, 8])
        XCTAssertEqual(preparation.points[1].progress, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(preparation.extrema, IntradayExtremaSelection(buyIndex: 1, sellIndex: 0))
        XCTAssertLessThan(preparation.low, 7)
        XCTAssertGreaterThan(preparation.high, 10)
    }

    func testSkipsExtremaWorkWhenMarkersAreHidden() throws {
        let preparation = IntradayChartPreparation(
            points: [
                bar(hour: 9, minute: 30, close: 10),
                bar(hour: 10, minute: 0, close: 7),
                bar(hour: 10, minute: 30, close: 8),
            ],
            market: .aShare,
            dayOpen: 9,
            previousClose: 8,
            showBSMarkers: false
        )

        XCTAssertNil(preparation.extrema)
    }

    private func bar(hour: Int, minute: Int, close: Double) -> MinuteBar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.aShare.timeZone
        let time = calendar.date(from: DateComponents(
            timeZone: Market.aShare.timeZone,
            year: 2026,
            month: 8,
            day: 12,
            hour: hour,
            minute: minute
        ))!
        return MinuteBar(time: time, open: close, close: close, high: close, low: close)
    }
}
