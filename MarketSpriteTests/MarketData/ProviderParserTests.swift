import XCTest
@testable import MarketSprite

final class ProviderParserTests: XCTestCase {
    func testEastMoneyParserReadsActualTrendLayout() throws {
        let raw = "2026-07-30 09:31,1323.00,1329.50,1330.00,1322.00,753,99792267.00,1324.911"
        let bar = try XCTUnwrap(
            EastMoneyParser.minuteBar(from: raw)
        )

        XCTAssertEqual(bar.open, 1323, accuracy: 0.001)
        XCTAssertEqual(bar.close, 1329.5, accuracy: 0.001)
        XCTAssertEqual(bar.high, 1330, accuracy: 0.001)
        XCTAssertEqual(bar.low, 1322, accuracy: 0.001)
    }

    func testEastMoneyUSMinutesUseProviderClockAndStayInOneMarketSession() throws {
        let open = try XCTUnwrap(
            EastMoneyParser.minuteBar(
                from: "2026-07-30 21:30,209.00,209.20,209.30,208.90,1,1,1"
            )
        )
        let close = try XCTUnwrap(
            EastMoneyParser.minuteBar(
                from: "2026-07-31 04:00,209.20,210.00,210.10,209.10,1,1,1"
            )
        )

        XCTAssertEqual(
            open.time,
            ISO8601DateFormatter().date(from: "2026-07-30T13:30:00Z")
        )
        XCTAssertEqual(
            close.time,
            ISO8601DateFormatter().date(from: "2026-07-30T20:00:00Z")
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: open.time, market: .unitedStates),
            "2026-07-30"
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: close.time, market: .unitedStates),
            "2026-07-30"
        )
    }

    func testTencentParserReadsActualMinuteLayoutInMarketTimeZone() throws {
        let bar = try XCTUnwrap(
            TencentParser.minuteBar(
                from: "0931 1329.50 961 127323916.11",
                date: "20260730",
                market: .aShare
            )
        )

        XCTAssertEqual(bar.close, 1329.5, accuracy: 0.001)
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: bar.time, market: .aShare),
            "2026-07-30"
        )
    }

    func testProviderMappingsCoverAllSupportedMarkets() {
        XCTAssertEqual(
            TencentParser.code(for: Instrument.initialWatchlist[0]),
            "sh600519"
        )
        XCTAssertEqual(
            TencentParser.code(for: Instrument.initialWatchlist[1]),
            "hk00700"
        )
        XCTAssertEqual(
            TencentParser.code(for: Instrument.initialWatchlist[2]),
            "usAAPL"
        )

        XCTAssertEqual(
            EastMoneyParser.quoteIdentifier(for: Instrument.initialWatchlist[0]),
            "1.600519"
        )
        XCTAssertEqual(
            EastMoneyParser.quoteIdentifier(for: Instrument.initialWatchlist[1]),
            "116.00700"
        )
        XCTAssertEqual(
            EastMoneyParser.quoteIdentifier(for: Instrument.initialWatchlist[2]),
            "105.AAPL"
        )

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
        let beijingStock = Instrument(
            symbol: "920001",
            name: "纬达光电",
            namespace: .beijing
        )
        XCTAssertEqual(TencentParser.code(for: shanghaiIndex), "sh000001")
        XCTAssertEqual(TencentParser.code(for: shenzhenStock), "sz000001")
        XCTAssertEqual(TencentParser.code(for: beijingStock), "bj920001")
        XCTAssertEqual(EastMoneyParser.quoteIdentifier(for: shanghaiIndex), "1.000001")
        XCTAssertEqual(EastMoneyParser.quoteIdentifier(for: shenzhenStock), "0.000001")
        XCTAssertEqual(EastMoneyParser.quoteIdentifier(for: beijingStock), "0.920001")
    }

    func testEastMoneySearchItemsMapOnlyToSupportedNamespaces() {
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "600519",
                    name: "贵州茅台",
                    classification: "AStock",
                    marketNumber: "1",
                    quoteIdentifier: "1.600519"
                )
            ),
            .shanghai
        )
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "00700",
                    name: "腾讯控股",
                    classification: "HK",
                    marketNumber: "116",
                    quoteIdentifier: "116.00700"
                )
            ),
            .hongKong
        )
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "AAPL",
                    name: "苹果",
                    classification: "UsStock",
                    marketNumber: "105",
                    quoteIdentifier: "105.AAPL"
                )
            ),
            .unitedStates
        )

        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "000001",
                    name: "平安银行",
                    classification: "AStock",
                    marketNumber: "0",
                    quoteIdentifier: "0.000001"
                )
            ),
            .shenzhen
        )
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "920001",
                    name: "纬达光电",
                    classification: "NEEQ",
                    marketNumber: "0",
                    quoteIdentifier: "0.920001"
                )
            ),
            .beijing
        )
        XCTAssertNil(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "000001",
                    name: "场外基金",
                    classification: "OTCFUND",
                    marketNumber: "150",
                    quoteIdentifier: "150.000001"
                )
            )
        )
    }
}
