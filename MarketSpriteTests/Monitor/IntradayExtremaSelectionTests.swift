import XCTest
@testable import MarketSprite

final class IntradayExtremaSelectionTests: XCTestCase {
    func testStrictlyFallingSessionHasOnlySellExtremum() {
        let selection = IntradayExtremaSelection(closes: [10, 9, 8])

        XCTAssertNil(selection.buyIndex)
        XCTAssertEqual(selection.sellIndex, 0)
    }

    func testFlatSessionHasNoExtremaMarkers() {
        let selection = IntradayExtremaSelection(closes: [8, 8, 8])

        XCTAssertNil(selection.buyIndex)
        XCTAssertNil(selection.sellIndex)
    }

    func testStrictlyRisingSessionUsesFirstAndLastPoints() {
        let selection = IntradayExtremaSelection(closes: [8, 9, 10])

        XCTAssertEqual(selection.buyIndex, 0)
        XCTAssertEqual(selection.sellIndex, 2)
    }

    func testRecoveredLowIsSelectedAlongsideIndependentHigh() {
        let selection = IntradayExtremaSelection(closes: [10, 7, 8])

        XCTAssertEqual(selection.buyIndex, 1)
        XCTAssertEqual(selection.sellIndex, 0)
    }

    func testUnrecoveredClosingLowIsNotSelectedAsBuyExtremum() {
        let selection = IntradayExtremaSelection(closes: [10, 7, 8, 6])

        XCTAssertNil(selection.buyIndex)
        XCTAssertEqual(selection.sellIndex, 0)
    }

    func testRepeatedHighAndLowUseTheirFirstOccurrences() {
        let selection = IntradayExtremaSelection(closes: [10, 7, 7, 8, 10])

        XCTAssertEqual(selection.buyIndex, 1)
        XCTAssertEqual(selection.sellIndex, 0)
    }

    func testFewerThanTwoPointsHasNoExtremaMarkers() {
        for closes in [[], [8.0]] {
            let selection = IntradayExtremaSelection(closes: closes)

            XCTAssertNil(selection.buyIndex)
            XCTAssertNil(selection.sellIndex)
        }
    }
}
