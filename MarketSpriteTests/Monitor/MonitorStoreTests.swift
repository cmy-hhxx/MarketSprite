import XCTest
@testable import MarketSprite

@MainActor
final class MonitorStoreTests: XCTestCase {
    func testCachedQuoteRemainsVisibleAndBecomesStaleWhenRefreshFails() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(for: instrument, price: 210)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.instruments, [instrument])
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        store.stop()
    }

    func testAddingMoreThanTenInstrumentsPersistsTheWholeWatchlist() async throws {
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [])
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()

        for index in 0..<12 {
            let instrument = Instrument(
                symbol: "TEST\(index)",
                name: "测试\(index)",
                namespace: .unitedStates
            )
            let error = await store.add(instrument)
            XCTAssertNil(error)
        }

        let persisted = try await database.loadWatchlist()
        XCTAssertEqual(store.instruments.count, 12)
        XCTAssertEqual(persisted, store.instruments)
        store.stop()
    }

    func testConcurrentAddsPreserveEveryInstrument() async throws {
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [])
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let instruments = (0..<20).map {
            Instrument(
                symbol: "RACE\($0)",
                name: "并发测试\($0)",
                namespace: .unitedStates
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for instrument in instruments {
                group.addTask {
                    let error = await store.add(instrument)
                    XCTAssertNil(error)
                }
            }
        }

        let persisted = try await database.loadWatchlist()
        XCTAssertEqual(Set(store.instruments), Set(instruments))
        XCTAssertEqual(Set(persisted), Set(instruments))
        XCTAssertEqual(persisted, store.instruments)
        store.stop()
    }

    func testSuccessfulRefreshUpdatesQuoteBarCountImmediately() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let quote = makeQuote(for: instrument, price: 210)
        try await database.replaceWatchlist(with: [instrument])
        let store = MonitorStore(
            client: StaticMarketDataClient(quote: quote),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()

        XCTAssertEqual(store.quoteBarCount, 2)
        store.stop()
    }

    func testOneSuccessfulQuoteDoesNotHideAnotherQuotePersistenceFailure() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory
            .appendingPathComponent("mixed-quote-save.sqlite")
            .path
        let rejected = Instrument(
            symbol: "REJECTED",
            name: "拒绝写入",
            namespace: .unitedStates
        )
        let accepted = Instrument(
            symbol: "ACCEPTED",
            name: "允许写入",
            namespace: .unitedStates
        )
        try await prepareDatabase(
            atPath: databasePath,
            watchlist: [rejected, accepted]
        )
        try SQLiteTestSupport.execute(
            """
            CREATE TRIGGER reject_one_quote
            BEFORE INSERT ON quote_sessions
            WHEN NEW.instrument_id = 'us:REJECTED'
            BEGIN
                SELECT RAISE(ABORT, 'forced quote persistence failure');
            END;
            """,
            atPath: databasePath
        )
        let database = try MarketDatabase.open(atPath: databasePath)
        let store = MonitorStore(
            client: DelayedPerInstrumentMarketDataClient(
                quotes: [
                    rejected.id: makeQuote(for: rejected, price: 110),
                    accepted.id: makeQuote(for: accepted, price: 120),
                ],
                delayedInstrumentID: accepted.id
            ),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()

        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(
            store.monitoredInstrument(for: rejected.id)?.quote?.lastPrice,
            110
        )
        XCTAssertEqual(
            store.monitoredInstrument(for: accepted.id)?.quote?.lastPrice,
            120
        )
        XCTAssertEqual(store.quoteBarCount, 2)
        await store.refreshQuoteBarCount()
        XCTAssertNotNil(store.storageError)
        store.stop()
        try await database.close()
    }

    func testOlderProviderSnapshotDoesNotReplaceNewerCachedQuote() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(
            for: instrument,
            price: 210,
            at: Date(timeIntervalSince1970: 1_700_000_120)
        )
        let older = makeQuote(
            for: instrument,
            price: 205,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let store = MonitorStore(
            client: StaticMarketDataClient(quote: older),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()

        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        store.stop()
    }

    func testChangingOnePriceTargetDoesNotRearmOtherInstruments() async throws {
        let database = try MarketDatabase.inMemory()
        let first = Instrument(symbol: "AAA", name: "甲", namespace: .unitedStates)
        let second = Instrument(symbol: "BBB", name: "乙", namespace: .unitedStates)
        let firstQuote = makeQuote(for: first, price: 110)
        let secondQuote = makeQuote(for: second, price: 110)
        try await database.replaceWatchlist(with: [first, second])
        try await database.saveAlertConfiguration(
            AlertConfiguration(
                isEnabled: true,
                basis: .targetPrice,
                risingThreshold: 3,
                fallingThreshold: 3
            )
        )
        try await database.replacePriceAlertTargets([
            first.id: PriceAlertTargets(risingPrice: 105, fallingPrice: 0),
            second.id: PriceAlertTargets(risingPrice: 105, fallingPrice: 0),
        ])
        let store = MonitorStore(
            client: DelayedPerInstrumentMarketDataClient(
                quotes: [first.id: firstQuote, second.id: secondQuote],
                delayedInstrumentID: second.id
            ),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        XCTAssertEqual(store.activeAlert?.instrument.id, second.id)

        store.updatePriceTargets(
            for: first,
            risingPrice: 106,
            fallingPrice: 0
        )
        await store.refreshAll()

        XCTAssertEqual(store.activeAlert?.instrument.id, first.id)
        store.stop()
    }

    func testAlertPersistenceFailureRollsBackAndSurvivesEmptyRefresh() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory
            .appendingPathComponent("readonly.sqlite")
            .path
        var writableDatabase: MarketDatabase? = try MarketDatabase.open(
            atPath: databasePath
        )
        try await writableDatabase?.replaceWatchlist(with: [])
        try await writableDatabase?.close()
        writableDatabase = nil
        let database = try MarketDatabase.openReadOnly(atPath: databasePath)
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let persisted = store.alertConfiguration
        var changed = persisted
        changed.isEnabled.toggle()

        store.updateAlertConfiguration(changed)
        for _ in 0..<100 where store.storageError == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(store.alertConfiguration, persisted)
        XCTAssertNotNil(store.storageError)
        await store.refreshAll()
        XCTAssertNotNil(store.storageError)
        store.stop()
        try await database.close()
    }

    func testRemovedInstrumentCannotCommitDelayedRefresh() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument(
            symbol: "REMOVE",
            name: "待删除",
            namespace: .unitedStates
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveAlertConfiguration(
            AlertConfiguration(
                isEnabled: true,
                basis: .targetPrice,
                risingThreshold: 3,
                fallingThreshold: 3
            )
        )
        try await database.replacePriceAlertTargets([
            instrument.id: PriceAlertTargets(risingPrice: 100, fallingPrice: 0),
        ])
        let client = OneShotSuspendingMarketDataClient()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await client.suspendNextFetch(
            with: makeQuote(for: instrument, price: 110)
        )
        let refreshTask = Task { await store.refreshAll() }
        await client.waitUntilFetchIsSuspended()

        await store.remove(instrument)
        await client.resumeSuspendedFetch()
        await refreshTask.value
        let quoteBarCount = try await database.quoteBarCount()

        XCTAssertTrue(store.instruments.isEmpty)
        XCTAssertNil(store.monitoredInstrument(for: instrument.id))
        XCTAssertNil(store.activeAlert)
        XCTAssertEqual(quoteBarCount, 0)
        store.stop()
    }

    func testImportedWatchlistCannotCommitDiscardedInstrumentDelayedRefresh() async throws {
        let database = try MarketDatabase.inMemory()
        let discarded = Instrument(
            symbol: "OLD",
            name: "旧标的",
            namespace: .unitedStates
        )
        let imported = Instrument(
            symbol: "NEW",
            name: "新标的",
            namespace: .unitedStates
        )
        try await database.replaceWatchlist(with: [discarded])
        try await database.saveAlertConfiguration(
            AlertConfiguration(
                isEnabled: true,
                basis: .targetPrice,
                risingThreshold: 3,
                fallingThreshold: 3
            )
        )
        try await database.replacePriceAlertTargets([
            discarded.id: PriceAlertTargets(risingPrice: 100, fallingPrice: 0),
        ])
        let client = OneShotSuspendingMarketDataClient()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await client.suspendNextFetch(
            with: makeQuote(for: discarded, price: 110)
        )
        let refreshTask = Task { await store.refreshAll() }
        await client.waitUntilFetchIsSuspended()
        let json = String(
            data: try JSONEncoder().encode([imported]),
            encoding: .utf8
        )!

        let result = await store.importWatchlist(fromJSON: json)
        await client.resumeSuspendedFetch()
        await refreshTask.value
        let quoteBarCount = try await database.quoteBarCount()

        XCTAssertEqual(result, .success(count: 1))
        XCTAssertEqual(store.instruments, [imported])
        XCTAssertNil(store.monitoredInstrument(for: discarded.id))
        XCTAssertNil(store.activeAlert)
        XCTAssertEqual(quoteBarCount, 0)
        store.stop()
    }

    private func makePreferences() -> AppPreferences {
        let suiteName = "MarketSpriteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppPreferences(defaults: defaults)
    }

    private func prepareDatabase(
        atPath path: String,
        watchlist: [Instrument]
    ) async throws {
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: watchlist)
        try await database.close()
    }

    private func makeQuote(
        for instrument: Instrument,
        price: Double,
        at time: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> QuoteSnapshot {
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [
                MinuteBar(
                    time: time,
                    open: price - 1,
                    close: price,
                    high: price + 1,
                    low: price - 2
                ),
                MinuteBar(
                    time: time.addingTimeInterval(60),
                    open: price,
                    close: price,
                    high: price + 1,
                    low: price - 1
                ),
            ],
            dayOpen: price - 1,
            previousClose: price - 2,
            lastPrice: price,
            marketTime: time.addingTimeInterval(60),
            receivedAt: time.addingTimeInterval(61),
            source: .tencent
        )
    }
}

private struct FailingMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        throw URLError(.notConnectedToInternet)
    }
}

private struct StaticMarketDataClient: MarketDataClient {
    let quote: QuoteSnapshot

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        quote
    }
}

private struct DelayedPerInstrumentMarketDataClient: MarketDataClient {
    let quotes: [InstrumentID: QuoteSnapshot]
    let delayedInstrumentID: InstrumentID

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        if instrument.id == delayedInstrumentID {
            try await Task.sleep(for: .milliseconds(30))
        }
        guard let quote = quotes[instrument.id] else {
            throw MarketDataError.invalidResponse
        }
        return quote
    }
}

private actor OneShotSuspendingMarketDataClient: MarketDataClient {
    private var nextQuote: QuoteSnapshot?
    private var suspendedFetch: (
        quote: QuoteSnapshot,
        continuation: CheckedContinuation<QuoteSnapshot, Error>
    )?

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        guard let quote = nextQuote, quote.instrumentID == instrument.id else {
            throw URLError(.notConnectedToInternet)
        }
        nextQuote = nil
        return try await withCheckedThrowingContinuation { continuation in
            suspendedFetch = (quote, continuation)
        }
    }

    func suspendNextFetch(with quote: QuoteSnapshot) {
        nextQuote = quote
    }

    func waitUntilFetchIsSuspended() async {
        while suspendedFetch == nil {
            await Task.yield()
        }
    }

    func resumeSuspendedFetch() {
        guard let suspendedFetch else { return }
        self.suspendedFetch = nil
        suspendedFetch.continuation.resume(returning: suspendedFetch.quote)
    }
}
