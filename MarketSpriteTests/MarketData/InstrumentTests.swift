import XCTest
@testable import MarketSprite

final class InstrumentTests: XCTestCase {
    func testInstrumentIdentityIsStableAndProviderIndependent() {
        let instrument = Instrument(
            symbol: " aapl ",
            name: " Apple ",
            namespace: .unitedStates
        )

        XCTAssertEqual(instrument.id, InstrumentID(rawValue: "us:AAPL"))
        XCTAssertEqual(instrument.symbol, "AAPL")
        XCTAssertEqual(instrument.name, "Apple")
        XCTAssertEqual(instrument.market, .unitedStates)
    }

    func testSameAShareSymbolOnDifferentExchangesHasDifferentIdentity() {
        let shanghaiIndex = Instrument(
            symbol: "000001",
            name: "上证指数",
            namespace: .shanghai
        )
        let shenzhenStock = Instrument(
            symbol: "000001",
            name: "平安银行",
            namespace: .shenzhen
        )

        XCTAssertEqual(shanghaiIndex.id, InstrumentID(rawValue: "sse:000001"))
        XCTAssertEqual(shenzhenStock.id, InstrumentID(rawValue: "szse:000001"))
        XCTAssertNotEqual(shanghaiIndex.id, shenzhenStock.id)
    }

    func testInstrumentJSONDoesNotPersistProviderIdentifiers() throws {
        let instrument = Instrument(
            symbol: "600519",
            name: "贵州茅台",
            namespace: .shanghai
        )

        let data = try JSONEncoder().encode(instrument)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["name", "namespace", "symbol"])
        XCTAssertEqual(object["namespace"] as? String, "sse")
        XCTAssertEqual(try JSONDecoder().decode(Instrument.self, from: data), instrument)
    }
}
