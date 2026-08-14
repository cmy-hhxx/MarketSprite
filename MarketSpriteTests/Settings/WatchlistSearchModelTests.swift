import XCTest
@testable import MarketSprite

@MainActor
final class WatchlistSearchModelTests: XCTestCase {
    func testLatestRequestWinsWhenEarlierRequestCompletesLate() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "旧查询"
        model.submit()
        await harness.waitUntilStarted(count: 1)

        model.query = "新查询"
        model.submit()
        await harness.waitUntilStarted(count: 2)

        let expected = Self.instrument(symbol: "NEW")
        await harness.resolve(query: "新查询", with: [expected])
        await waitUntil { model.results == [expected] }

        await harness.resolve(query: "旧查询", with: [Self.instrument(symbol: "OLD")])
        await Task.yield()

        XCTAssertEqual(model.results, [expected])
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
    }

    func testEditingQueryCancelsInFlightSearchWithoutShowingFailure() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "旧查询"
        model.submit()
        await harness.waitUntilStarted(count: 1)

        model.query = "新查询"
        await harness.waitUntilCancelled(query: "旧查询")

        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
    }

    func testFailedSearchCanRetryTheSameQuery() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "AAPL"
        model.submit()
        await harness.waitUntilStarted(count: 1)
        await harness.fail(query: "AAPL", with: URLError(.notConnectedToInternet))
        await waitUntil { model.message != nil }

        model.submit()
        await harness.waitUntilStarted(count: 2)
        let expected = Self.instrument(symbol: "AAPL")
        await harness.resolve(query: "AAPL", with: [expected])
        await waitUntil { model.results == [expected] }

        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
    }

    func testSearchResultsAreDeduplicatedByInstrumentIdentity() async {
        let expected = Self.instrument(symbol: "AAPL")
        let model = WatchlistSearchModel { _ in [expected, expected] }

        model.query = "AAPL"
        model.submit()
        await waitUntil { !model.isSearching }

        XCTAssertEqual(model.results, [expected])
    }

    func testCancelStopsTheInFlightRequest() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "AAPL"
        model.submit()
        await harness.waitUntilStarted(count: 1)
        model.cancel()
        await harness.waitUntilCancelled(query: "AAPL")

        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.message)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }

    private static func instrument(symbol: String) -> Instrument {
        Instrument(symbol: symbol, name: "测试 \(symbol)", namespace: .unitedStates)
    }
}

private actor SearchHarness {
    private var startedQueries: [String] = []
    private var cancelledQueries = Set<String>()
    private var continuations: [String: CheckedContinuation<[Instrument], Error>] = [:]

    func search(_ query: String) async throws -> [Instrument] {
        startedQueries.append(query)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[query] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(of: query) }
        }
    }

    func resolve(query: String, with instruments: [Instrument]) {
        let continuation = continuations.removeValue(forKey: query)
        continuation?.resume(returning: instruments)
    }

    func fail(query: String, with error: Error) {
        let continuation = continuations.removeValue(forKey: query)
        continuation?.resume(throwing: error)
    }

    func waitUntilStarted(count: Int) async {
        while startedQueries.count < count {
            await Task.yield()
        }
    }

    func waitUntilCancelled(query: String) async {
        while !cancelledQueries.contains(query) {
            await Task.yield()
        }
    }

    private func recordCancellation(of query: String) {
        cancelledQueries.insert(query)
    }
}
