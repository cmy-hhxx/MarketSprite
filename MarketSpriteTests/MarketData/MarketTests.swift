import XCTest
@testable import MarketSprite

final class MarketTests: XCTestCase {
    func testPriceColorConventionMatchesEachMarket() {
        XCTAssertEqual(Market.aShare.colorRole(isRising: true), .red)
        XCTAssertEqual(Market.hongKong.colorRole(isRising: true), .red)
        XCTAssertEqual(Market.unitedStates.colorRole(isRising: true), .green)
        XCTAssertEqual(Market.aShare.colorRole(isRising: false), .green)
        XCTAssertEqual(Market.unitedStates.colorRole(isRising: false), .red)
    }
}
