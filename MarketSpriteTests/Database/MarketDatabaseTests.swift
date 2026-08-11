import XCTest
@testable import MarketSprite

final class MarketDatabaseTests: XCTestCase {
    func testDefaultWatchlistIsSeededOnlyOnFirstLaunch() async throws {
        let database = try MarketDatabase.inMemory()

        let firstLoad = try await database.loadWatchlist(
            defaultingTo: Instrument.initialWatchlist
        )
        XCTAssertEqual(firstLoad, Instrument.initialWatchlist)

        try await database.replaceWatchlist(with: [])

        let laterLoad = try await database.loadWatchlist(
            defaultingTo: Instrument.initialWatchlist
        )
        XCTAssertEqual(laterLoad, [])
    }

    func testWatchlistRoundTripsInUserDefinedOrder() async throws {
        let database = try MarketDatabase.inMemory()
        let watchlist = [
            Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates),
            Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai),
            Instrument(symbol: "00700", name: "腾讯控股", namespace: .hongKong),
        ]

        let initiallyLoaded = try await database.loadWatchlist()
        XCTAssertEqual(initiallyLoaded, [])

        try await database.replaceWatchlist(with: watchlist)

        let loaded = try await database.loadWatchlist()
        XCTAssertEqual(loaded, watchlist)
    }

    func testWatchlistKeepsSameSymbolFromDifferentNamespaces() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = [
            Instrument(symbol: "000001", name: "上证指数", namespace: .shanghai),
            Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen),
        ]

        try await database.replaceWatchlist(with: instruments)

        let loaded = try await database.loadWatchlist()
        XCTAssertEqual(loaded, instruments)
    }

    func testReplacingWatchlistRemovesItemsThatAreNoLongerObserved() async throws {
        let database = try MarketDatabase.inMemory()
        let first = Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai)
        let second = Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates)

        try await database.replaceWatchlist(with: [first, second])
        try await database.replaceWatchlist(with: [second])

        let loaded = try await database.loadWatchlist()
        XCTAssertEqual(loaded, [second])
    }

    func testLatestQuotesForEverySupportedMarketRoundTrip() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = Instrument.initialWatchlist
        try await database.replaceWatchlist(with: instruments)

        let snapshots = [
            quote(
                for: instruments[0],
                price: 1_500,
                at: "2026-07-30T07:00:00Z",
                source: .tencent
            ),
            quote(
                for: instruments[1],
                price: 510,
                at: "2026-07-30T08:00:00Z",
                source: .eastMoney
            ),
            quote(
                for: instruments[2],
                price: 210,
                at: "2026-07-30T20:00:00Z",
                source: .tencent
            ),
        ]

        for (instrument, snapshot) in zip(instruments, snapshots) {
            try await database.saveQuote(snapshot, for: instrument)
        }

        let loaded = try await database.loadLatestQuotes(for: instruments)
        let barCount = try await database.quoteBarCount()

        XCTAssertEqual(loaded, Dictionary(uniqueKeysWithValues: snapshots.map { ($0.instrumentID, $0) }))
        XCTAssertEqual(barCount, 3)
    }

    func testSavingTheSameSessionReplacesBarsAndClearRemovesAllQuoteData() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let first = quote(
            for: instrument,
            price: 1_500,
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let replacement = quote(
            for: instrument,
            price: 1_510,
            at: "2026-07-30T07:01:00Z",
            source: .eastMoney
        )

        try await database.saveQuote(first, for: instrument)
        try await database.saveQuote(replacement, for: instrument)

        let replaced = try await database.loadLatestQuotes(for: [instrument])
        let replacedCount = try await database.quoteBarCount()
        XCTAssertEqual(replaced[instrument.id], replacement)
        XCTAssertEqual(replacedCount, 1)

        try await database.clearQuotes()

        let cleared = try await database.loadLatestQuotes(for: [instrument])
        let clearedCount = try await database.quoteBarCount()
        XCTAssertEqual(cleared, [:])
        XCTAssertEqual(clearedCount, 0)
    }

    func testSavingAQuoteRejectsAMismatchedInstrumentIdentity() async throws {
        let database = try MarketDatabase.inMemory()
        let expectedInstrument = Instrument.initialWatchlist[0]
        let otherInstrument = Instrument.initialWatchlist[2]
        let snapshot = quote(
            for: otherInstrument,
            price: 210,
            at: "2026-07-30T20:00:00Z",
            source: .tencent
        )

        do {
            try await database.saveQuote(snapshot, for: expectedInstrument)
            XCTFail("Expected MarketDatabase to reject a mismatched quote identity")
        } catch MarketDatabaseError.quoteInstrumentMismatch(let expected, let actual) {
            XCTAssertEqual(expected, expectedInstrument.id)
            XCTAssertEqual(actual, otherInstrument.id)
        }
    }

    func testQuoteIsNotSavedAfterInstrumentLeavesWatchlist() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        try await database.replaceWatchlist(with: [])
        let snapshot = quote(
            for: instrument,
            price: 1_500,
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )

        let saved = try await database.saveQuote(snapshot, for: instrument)
        let barCount = try await database.quoteBarCount()

        XCTAssertFalse(saved)
        XCTAssertEqual(barCount, 0)
    }

    func testSavingAnExtendedSessionAppendsNewBarsAndRefreshesTheLastMinute() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let first = quote(
            for: instrument,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let extended = quote(
            for: instrument,
            prices: [1_500, 1_502, 1_503],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )

        try await database.saveQuote(first, for: instrument)
        try await database.saveQuote(extended, for: instrument)

        let loaded = try await database.loadLatestQuotes(for: [instrument])
        let barCount = try await database.quoteBarCount()
        XCTAssertEqual(loaded[instrument.id], extended)
        XCTAssertEqual(barCount, 3)
    }

    func testSameRangeSourceSwitchCorrectsEarlierBarsExactly() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let original = quote(
            for: instrument,
            prices: [1_500, 1_501, 1_502],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        var correctedBars = original.minuteBars
        correctedBars[1] = MinuteBar(
            time: correctedBars[1].time,
            open: 1_510,
            close: 1_511,
            high: 1_512,
            low: 1_509
        )
        let corrected = replacing(
            original,
            bars: correctedBars,
            lastPrice: correctedBars.last?.close ?? original.lastPrice,
            source: .eastMoney
        )

        try await database.saveQuote(original, for: instrument)
        try await database.saveQuote(corrected, for: instrument)

        let loaded = try await database.loadLatestQuotes(for: [instrument])
        let count = try await database.quoteBarCount()
        XCTAssertEqual(loaded[instrument.id], corrected)
        XCTAssertEqual(count, 3)
    }

    func testShrinkingSnapshotDeletesOrphanedMinutes() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let original = quote(
            for: instrument,
            prices: [1_500, 1_501, 1_502],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let bars = Array(original.minuteBars.prefix(2))
        let shortened = replacing(
            original,
            bars: bars,
            lastPrice: bars.last?.close ?? original.lastPrice,
            source: .tencent
        )

        try await database.saveQuote(original, for: instrument)
        try await database.saveQuote(shortened, for: instrument)

        let loaded = try await database.loadLatestQuotes(for: [instrument])
        let count = try await database.quoteBarCount()
        XCTAssertEqual(loaded[instrument.id], shortened)
        XCTAssertEqual(count, 2)
    }

    func testInvalidMinuteSnapshotIsRejectedWithoutPartialWrites() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let valid = quote(
            for: instrument,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let duplicate = replacing(
            valid,
            bars: [valid.minuteBars[0], valid.minuteBars[0]],
            lastPrice: valid.lastPrice,
            source: valid.source
        )

        await XCTAssertThrowsErrorAsync {
            try await database.saveQuote(duplicate, for: instrument)
        }
        let count = try await database.quoteBarCount()
        let loaded = try await database.loadLatestQuotes(for: [instrument])
        XCTAssertEqual(count, 0)
        XCTAssertEqual(loaded, [:])
    }

    func testAlertConfigurationAndPerInstrumentTargetsRoundTrip() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        try await database.replaceWatchlist(with: [instrument])

        let initialSettings = try await database.loadAlertSettings(for: [instrument])
        XCTAssertEqual(initialSettings, .default)

        let configuration = AlertConfiguration(
            isEnabled: false,
            basis: .targetPrice,
            risingThreshold: 4.5,
            fallingThreshold: 2.5
        )
        let targets = PriceAlertTargets(risingPrice: 220, fallingPrice: 190)
        let settings = AlertSettingsSnapshot(
            configuration: configuration,
            priceTargets: [instrument.id: targets]
        )
        try await database.saveAlertSettings(settings)

        let loadedSettings = try await database.loadAlertSettings(for: [instrument])
        XCTAssertEqual(loadedSettings, settings)
    }

    func testFileDatabaseReopensWithNamespaceWatchlistQuoteAndTargets() async throws {
        XCTAssertEqual(MarketDatabase.defaultFileName, "marketsprite-v3.sqlite")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory
            .appendingPathComponent(MarketDatabase.defaultFileName)
            .path
        let instruments = [
            Instrument(symbol: "000001", name: "上证指数", namespace: .shanghai),
            Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen),
        ]
        let snapshot = quote(
            for: instruments[0],
            price: 3_500,
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let targets = PriceAlertTargets(risingPrice: 3_600, fallingPrice: 3_400)

        try await writeDatabaseFixture(
            atPath: databasePath,
            instruments: instruments,
            snapshot: snapshot,
            targets: targets
        )
        let reopened = try MarketDatabase.open(atPath: databasePath)
        let reopenedWatchlist = try await reopened.loadWatchlist()
        let reopenedQuotes = try await reopened.loadLatestQuotes(for: instruments)
        let reopenedSettings = try await reopened.loadAlertSettings(for: instruments)

        XCTAssertEqual(reopenedWatchlist, instruments)
        XCTAssertEqual(reopenedQuotes[instruments[0].id], snapshot)
        XCTAssertEqual(
            reopenedSettings.priceTargets,
            [instruments[0].id: targets]
        )
        try await reopened.close()
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteSchemaTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("unsupported.sqlite").path
        try SQLiteTestSupport.execute("PRAGMA user_version = 99;", atPath: path)

        XCTAssertThrowsError(try MarketDatabase.open(atPath: path)) { error in
            guard case MarketDatabaseError.unsupportedSchemaVersion(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func quote(
        for instrument: Instrument,
        price: Double,
        at timestamp: String,
        source: QuoteSource
    ) -> QuoteSnapshot {
        quote(
            for: instrument,
            prices: [price],
            at: timestamp,
            source: source
        )
    }

    private func writeDatabaseFixture(
        atPath path: String,
        instruments: [Instrument],
        snapshot: QuoteSnapshot,
        targets: PriceAlertTargets
    ) async throws {
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: instruments)
        let saved = try await database.saveQuote(snapshot, for: instruments[0])
        XCTAssertTrue(saved)
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [instruments[0].id: targets]
            )
        )
        try await database.close()
    }

    private func quote(
        for instrument: Instrument,
        prices: [Double],
        at timestamp: String,
        source: QuoteSource
    ) -> QuoteSnapshot {
        let marketTime = ISO8601DateFormatter().date(from: timestamp)!
        let bars = prices.enumerated().map { index, price in
            MinuteBar(
                time: marketTime.addingTimeInterval(Double(index) * 60),
                open: price - 1,
                close: price,
                high: price + 1,
                low: price - 2
            )
        }
        let lastPrice = prices.last ?? 0
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: (prices.first ?? 0) - 1,
            previousClose: (prices.first ?? 0) - 2,
            lastPrice: lastPrice,
            marketTime: bars.last?.time ?? marketTime,
            receivedAt: (bars.last?.time ?? marketTime).addingTimeInterval(1),
            source: source
        )
    }

    private func replacing(
        _ snapshot: QuoteSnapshot,
        bars: [MinuteBar],
        lastPrice: Double,
        source: QuoteSource
    ) -> QuoteSnapshot {
        QuoteSnapshot(
            instrumentID: snapshot.instrumentID,
            minuteBars: bars,
            dayOpen: snapshot.dayOpen,
            previousClose: snapshot.previousClose,
            lastPrice: lastPrice,
            marketTime: bars.last?.time ?? snapshot.marketTime,
            receivedAt: snapshot.receivedAt,
            source: source
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
