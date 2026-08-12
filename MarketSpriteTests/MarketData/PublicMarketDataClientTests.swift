import XCTest
@testable import MarketSprite

final class PublicMarketDataClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testSearchReturnsDeduplicatedProviderIndependentInstruments() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "searchapi.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                {
                  "QuotationCodeTable": {
                    "Data": [
                      {"Code":"AAPL","Name":"苹果","Classify":"UsStock","MktNum":"105","QuoteID":"105.AAPL"},
                      {"Code":"AAPL","Name":"苹果","Classify":"UsStock","MktNum":"105","QuoteID":"105.AAPL"}
                    ],
                    "Status": 0,
                    "Message": "OK"
                  }
                }
                """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())

        let instruments = try await client.searchInstruments(matching: " AAPL ")

        XCTAssertEqual(
            instruments,
            [Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates)]
        )
    }

    func testSearchKeepsSameSymbolFromDifferentAShareNamespaces() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "searchapi.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                {
                  "QuotationCodeTable": {
                    "Data": [
                      {"Code":"000001","Name":"平安银行","Classify":"AStock","MktNum":"0","QuoteID":"0.000001"},
                      {"Code":"000001","Name":"上证指数","Classify":"Index","MktNum":"1","QuoteID":"1.000001"}
                    ],
                    "Status": 0,
                    "Message": "OK"
                  }
                }
                """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())

        let instruments = try await client.searchInstruments(matching: "000001")

        XCTAssertEqual(
            instruments,
            [
                Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen),
                Instrument(symbol: "000001", name: "上证指数", namespace: .shanghai),
            ]
        )
    }

    func testQuoteFallsBackToEastMoneyWhenTencentFails() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.host == "web.ifzq.gtimg.cn" {
                return Self.response(for: request, json: "{}", statusCode: 503)
            }
            if request.url?.host == "searchapi.eastmoney.com" {
                return Self.response(
                    for: request,
                    json: """
                    {
                      "QuotationCodeTable": {
                        "Data": [
                          {"Code":"AAPL","Name":"苹果","Classify":"UsStock","MktNum":"105","QuoteID":"105.AAPL"}
                        ],
                        "Status": 0,
                        "Message": "OK"
                      }
                    }
                    """
                )
            }
            XCTAssertEqual(request.url?.host, "push2delay.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                {
                  "rc": 0,
                  "data": {
                    "preClose": 208.50,
                    "trends": [
                      "2026-07-30 21:30,209.00,209.20,209.30,208.90,1,1,1",
                      "2026-07-30 21:31,209.20,210.00,210.10,209.10,1,1,1"
                    ]
                  }
                }
                """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument.initialWatchlist[2]

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.minuteBars.count, 2)
        XCTAssertEqual(quote.lastPrice, 210, accuracy: 0.001)
        XCTAssertEqual(quote.previousClose, 208.5, accuracy: 0.001)
        XCTAssertEqual(
            quote.marketTime,
            ISO8601DateFormatter().date(from: "2026-07-30T13:31:00Z")
        )
    }

    func testProviderOHLCInconsistencyStillProducesPersistableSnapshot() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "QuotationCodeTable": {
                        "Data": [
                          {"Code":"AAPL","Name":"苹果","Classify":"UsStock","MktNum":"105","QuoteID":"105.AAPL"}
                        ],
                        "Status": 0,
                        "Message": "OK"
                      }
                    }
                    """
                )
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "rc": 0,
                      "data": {
                        "preClose": 306.90,
                        "trends": [
                          "2026-08-11 03:59,307.850,307.855,307.870,307.670,377815,116307446.000,307.1253",
                          "2026-08-11 04:00,307.855,308.260,308.250,307.800,10600910,3259890016.000,306.8981"
                        ]
                      }
                    }
                    """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument.initialWatchlist[2]
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [instrument])

        let quote = try await client.fetchQuote(for: instrument)
        let saved = try await database.saveQuote(quote, for: instrument)
        let lastBar = try XCTUnwrap(quote.minuteBars.last)

        XCTAssertTrue(saved)
        XCTAssertEqual(lastBar.close, 308.260, accuracy: 0.001)
        XCTAssertEqual(lastBar.high, 308.260, accuracy: 0.001)
    }

    func testUSFallbackResolvesItsProviderIdentifierWithoutPriorSearch() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "QuotationCodeTable": {
                        "Data": [
                          {"Code":"MSFT","Name":"微软","Classify":"UsStock","MktNum":"106","QuoteID":"106.MSFT"}
                        ],
                        "Status": 0,
                        "Message": "OK"
                      }
                    }
                    """
                )
            case "push2delay.eastmoney.com":
                let components = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "secid" })?.value,
                    "106.MSFT"
                )
                return Self.response(
                    for: request,
                    json: """
                    {
                      "rc": 0,
                      "data": {
                        "preClose": 500.00,
                        "trends": [
                          "2026-07-30 21:30,501.00,501.20,501.30,500.90,1,1,1",
                          "2026-07-30 21:31,501.20,502.00,502.10,501.10,1,1,1"
                        ]
                      }
                    }
                    """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument(symbol: "MSFT", name: "微软", namespace: .unitedStates)

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.lastPrice, 502, accuracy: 0.001)
    }

    func testShanghaiETFFallbackUsesNamespaceWithoutPriorSearch() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "code" })?.value,
                    "sh510300"
                )
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "push2delay.eastmoney.com":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "secid" })?.value,
                    "1.510300"
                )
                return Self.response(
                    for: request,
                    json: """
                    {
                      "rc": 0,
                      "data": {
                        "preClose": 4.20,
                        "trends": [
                          "2026-07-30 09:30,4.21,4.22,4.23,4.20,1,1,1",
                          "2026-07-30 09:31,4.22,4.24,4.25,4.21,1,1,1"
                        ]
                      }
                    }
                    """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument(
            symbol: "510300",
            name: "沪深300ETF华泰柏瑞",
            namespace: .shanghai
        )

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.lastPrice, 4.24, accuracy: 0.001)
    }

    func testBeijingSearchResultFetchesTencentBJCode() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "QuotationCodeTable": {
                        "Data": [
                          {"Code":"920001","Name":"纬达光电","Classify":"AStock","MktNum":"0","QuoteID":"0.920001"}
                        ],
                        "Status": 0,
                        "Message": "OK"
                      }
                    }
                    """
                )
            case "web.ifzq.gtimg.cn":
                let components = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "code" })?.value,
                    "bj920001"
                )
                return Self.response(
                    for: request,
                    json: """
                    {
                      "code": 0,
                      "data": {
                        "bj920001": {
                          "data": {
                            "data": [
                              "0930 10.00 1 1",
                              "0931 10.10 1 1"
                            ],
                            "date": "20260806"
                          },
                          "qt": {
                            "bj920001": ["", "", "", "10.10", "9.90", "10.00"]
                          }
                        }
                      }
                    }
                    """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        let searchResults = try await client.searchInstruments(matching: "920001")
        let instrument = try XCTUnwrap(searchResults.first)
        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(instrument.namespace, .beijing)
        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .tencent)
        XCTAssertEqual(quote.lastPrice, 10.10, accuracy: 0.001)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        json: String,
        statusCode: Int = 200
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(json.utf8))
    }
}
