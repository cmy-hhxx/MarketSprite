import XCTest
@testable import MarketSprite

@MainActor
final class AppBootstrapTests: XCTestCase {
    func testDatabaseOpenFailureDoesNotCreateAnInMemoryStore() async {
        let preferences = makePreferences()
        let bootstrap = AppBootstrap(
            preferences: preferences,
            databasePath: "/tmp/marketsprite.sqlite",
            databaseFactory: { throw TestError.databaseUnavailable }
        )

        await bootstrap.start()

        XCTAssertNil(bootstrap.store)
        XCTAssertEqual(bootstrap.failure?.databasePath, "/tmp/marketsprite.sqlite")
        XCTAssertNotNil(bootstrap.failure?.message)
    }

    func testLocalRestoreFailureDoesNotRefreshOrCreateAStore() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory
            .appendingPathComponent("invalid-restore.sqlite")
            .path
        try await prepareInvalidRestoreDatabase(atPath: databasePath)
        let client = CountingMarketDataClient()
        let bootstrap = AppBootstrap(
            preferences: makePreferences(),
            client: client,
            databasePath: databasePath,
            databaseFactory: { try MarketDatabase.open(atPath: databasePath) }
        )

        await bootstrap.start()
        let fetchCount = await client.fetchCount

        XCTAssertNil(bootstrap.store)
        XCTAssertNotNil(bootstrap.failure)
        XCTAssertEqual(fetchCount, 0)
    }

    private func makePreferences() -> AppPreferences {
        let suiteName = "MarketSpriteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppPreferences(defaults: defaults)
    }

    private func prepareInvalidRestoreDatabase(atPath path: String) async throws {
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [Instrument.initialWatchlist[0]])
        try await database.close()
        // Break the position invariant so the local restore fails on startup.
        try SQLiteTestSupport.execute(
            "UPDATE watchlist SET position = 999;",
            atPath: path
        )
    }
}

private enum TestError: Error {
    case databaseUnavailable
}

private actor CountingMarketDataClient: MarketDataClient {
    private(set) var fetchCount = 0

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        fetchCount += 1
        throw URLError(.notConnectedToInternet)
    }
}
