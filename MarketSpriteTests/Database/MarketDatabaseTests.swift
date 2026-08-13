import XCTest
@testable import MarketSprite

final class MarketDatabaseTests: XCTestCase {
    func testDefaultWatchlistIsSeededOnlyOnFirstLaunch() async throws {
        let database = try MarketDatabase.inMemory()

        let firstLoad = try await database.loadWatchlist()
        XCTAssertEqual(firstLoad, Instrument.initialWatchlist)

        try await database.replaceWatchlist(with: [])

        let laterLoad = try await database.loadWatchlist()
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
        XCTAssertEqual(initiallyLoaded, Instrument.initialWatchlist)

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

    func testRemovingAnInstrumentCascadesItsAlertsAndQuoteCache() async throws {
        let database = try MarketDatabase.inMemory()
        let first = Instrument.initialWatchlist[0]
        let second = Instrument.initialWatchlist[2]
        try await database.replaceWatchlist(with: [first, second])
        try await database.saveQuote(
            quote(for: first, price: 1_500, at: "2026-07-30T07:00:00Z", source: .tencent),
            for: first
        )
        try await database.saveQuote(
            quote(for: second, price: 210, at: "2026-07-30T20:00:00Z", source: .tencent),
            for: second
        )
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [
                    first.id: PriceAlertTargets(risingPrice: 1_600, fallingPrice: nil),
                    second.id: PriceAlertTargets(risingPrice: nil, fallingPrice: 200),
                ]
            )
        )

        try await database.replaceWatchlist(with: [second])

        let watchlist = try await database.loadWatchlist()
        let quotes = try await database.loadLatestQuotes(for: [first, second])
        let alerts = try await database.loadAlertSettings()
        XCTAssertEqual(watchlist, [second])
        XCTAssertEqual(quotes, [second.id: quote(for: second, price: 210, at: "2026-07-30T20:00:00Z", source: .tencent)])
        XCTAssertEqual(
            alerts.priceTargets,
            [second.id: PriceAlertTargets(risingPrice: nil, fallingPrice: 200)]
        )
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

    func testNewTradingDayReplacesThePriorCache() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let first = quote(
            for: instrument,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let nextDay = quote(
            for: instrument,
            prices: [1_600],
            at: "2026-07-31T07:00:00Z",
            source: .eastMoney
        )

        try await database.saveQuote(first, for: instrument)
        try await database.saveQuote(nextDay, for: instrument)

        let quotes = try await database.loadLatestQuotes(for: [instrument])
        let count = try await database.quoteBarCount()
        XCTAssertEqual(quotes, [instrument.id: nextDay])
        XCTAssertEqual(count, 1)
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

        let initialSettings = try await database.loadAlertSettings()
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

        let loadedSettings = try await database.loadAlertSettings()
        XCTAssertEqual(loadedSettings, settings)
    }

    func testFileDatabaseReopensWithNamespaceWatchlistQuoteAndTargets() async throws {
        XCTAssertEqual(MarketDatabase.defaultFileName, "marketsprite.sqlite")
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
        let reopenedSettings = try await reopened.loadAlertSettings()

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
        try SQLiteTestSupport.execute(
            "PRAGMA application_id = \(DatabaseSchema.applicationID); PRAGMA user_version = 99;",
            atPath: path
        )

        XCTAssertThrowsError(try MarketDatabase.open(atPath: path)) { error in
            guard case MarketDatabaseError.unsupportedSchemaVersion(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSchemaUsesFixedIdentityAndStrictConstraints() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteSchemaIdentity.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        _ = try MarketDatabase.open(atPath: path)

        try SQLiteTestSupport.execute(
            """
            PRAGMA application_id;
            PRAGMA user_version;
            SELECT sql FROM sqlite_schema WHERE name = 'watchlist';
            """,
            atPath: path
        )
        XCTAssertThrowsError(
            try SQLiteTestSupport.execute(
                "INSERT INTO alert_settings VALUES (2, 1, 'percentage', 3, 3);",
                atPath: path
            )
        )
        XCTAssertThrowsError(
            try SQLiteTestSupport.execute(
                "INSERT INTO price_alerts VALUES ('sse:600519', NULL, NULL);",
                atPath: path
            )
        )
    }

    func testLegacyDatabaseMovesToTheFixedCanonicalFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteLegacyMigration.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyPath = directory.appendingPathComponent("marketsprite-v3.sqlite").path
        try SQLiteTestSupport.execute(legacySchemaSQL, atPath: legacyPath)
        try SQLiteTestSupport.execute(
            """
            INSERT INTO instruments VALUES ('us:AAPL', 'AAPL', '苹果', 'us');
            INSERT INTO watchlist_items VALUES ('us:AAPL', 0);
            INSERT INTO alert_configuration VALUES (1, 1, 'targetPrice', 3, 3);
            INSERT INTO price_alert_targets VALUES ('us:AAPL', 250, 0);
            """,
            atPath: legacyPath
        )

        let database = try MarketDatabase.openInDirectory(directory)
        let watchlist = try await database.loadWatchlist()
        let settings = try await database.loadAlertSettings()
        XCTAssertEqual(watchlist, [
            Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates),
        ])
        XCTAssertEqual(
            settings,
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    InstrumentID(rawValue: "us:AAPL"):
                        PriceAlertTargets(risingPrice: 250, fallingPrice: nil),
                ]
            )
        )
        try await database.close()

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath))
        let backupNames = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backupNames.count, 1)
    }

    func testComprehensiveLegacyMigrationKeepsOnlyObservedLatestData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteLegacyMigrationComprehensive.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyPath = directory.appendingPathComponent("marketsprite-v3.sqlite").path
        try SQLiteTestSupport.execute(legacySchemaSQL, atPath: legacyPath)

        let apple = Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates)
        let maotai = Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai)
        let residual = Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen)
        let formatter = ISO8601DateFormatter()
        let dayA = formatter.date(from: "2026-07-30T07:00:00Z")!
        let dayB = formatter.date(from: "2026-07-31T07:00:00Z")!

        // Legacy fixture: two observed instruments plus one residual instrument that is
        // no longer on the watchlist; no alert_configuration row (defaults);
        // a single-direction target and a target for the removed instrument;
        // two trading days for AAPL with the older one carrying old time encoding.
        // Dates use GRDB's storage format "yyyy-MM-dd HH:mm:ss.SSS" (UTC), exactly
        // as the legacy database wrote them.
        try SQLiteTestSupport.execute(
            """
            INSERT INTO instruments VALUES ('us:AAPL', 'AAPL', '苹果', 'us');
            INSERT INTO instruments VALUES ('sse:600519', '600519', '贵州茅台', 'sse');
            INSERT INTO instruments VALUES ('szse:000001', '000001', '平安银行', 'szse');
            INSERT INTO watchlist_items VALUES ('us:AAPL', 0);
            INSERT INTO watchlist_items VALUES ('sse:600519', 1);
            INSERT INTO price_alert_targets VALUES ('us:AAPL', 250, 0);
            INSERT INTO price_alert_targets VALUES ('szse:000001', 12, 11);
            INSERT INTO quote_sessions VALUES ('us:AAPL', '2026-07-30', 1490, 1480, 1500, '\(storageDate.string(from: dayA))', '\(storageDate.string(from: dayA.addingTimeInterval(1)))', 'tencent');
            INSERT INTO minute_bars VALUES ('us:AAPL', '2026-07-30', '\(storageDate.string(from: dayA))', 1499, 1500, 1501, 1498);
            INSERT INTO quote_sessions VALUES ('us:AAPL', '2026-07-31', 1590, 1580, 1600, '\(storageDate.string(from: dayB))', '\(storageDate.string(from: dayB.addingTimeInterval(1)))', 'eastMoney');
            INSERT INTO minute_bars VALUES ('us:AAPL', '2026-07-31', '\(storageDate.string(from: dayB))', 1599, 1600, 1601, 1598);
            INSERT INTO quote_sessions VALUES ('sse:600519', '2026-07-30', 1700, 1690, 1710, '\(storageDate.string(from: dayA.addingTimeInterval(3600)))', '\(storageDate.string(from: dayA.addingTimeInterval(3601)))', 'tencent');
            INSERT INTO minute_bars VALUES ('sse:600519', '2026-07-30', '\(storageDate.string(from: dayA.addingTimeInterval(3600)))', 1709, 1710, 1711, 1708);
            """,
            atPath: legacyPath
        )

        let database = try MarketDatabase.openInDirectory(directory)
        let watchlist = try await database.loadWatchlist()
        let settings = try await database.loadAlertSettings()
        let quotes = try await database.loadLatestQuotes(for: [apple, maotai, residual])

        XCTAssertEqual(watchlist, [apple, maotai])
        XCTAssertEqual(settings.configuration, .default)
        XCTAssertEqual(
            settings.priceTargets,
            [apple.id: PriceAlertTargets(risingPrice: 250, fallingPrice: nil)]
        )
        XCTAssertEqual(quotes[apple.id], QuoteSnapshot(
            instrumentID: apple.id,
            minuteBars: [
                MinuteBar(time: dayB, open: 1599, close: 1600, high: 1601, low: 1598),
            ],
            dayOpen: 1590,
            previousClose: 1580,
            lastPrice: 1600,
            marketTime: dayB,
            receivedAt: dayB.addingTimeInterval(1),
            source: .eastMoney
        ))
        XCTAssertEqual(quotes[maotai.id], QuoteSnapshot(
            instrumentID: maotai.id,
            minuteBars: [
                MinuteBar(
                    time: dayA.addingTimeInterval(3600),
                    open: 1709,
                    close: 1710,
                    high: 1711,
                    low: 1708
                ),
            ],
            dayOpen: 1700,
            previousClose: 1690,
            lastPrice: 1710,
            marketTime: dayA.addingTimeInterval(3600),
            receivedAt: dayA.addingTimeInterval(3601),
            source: .tencent
        ))
        XCTAssertNil(quotes[residual.id])
        try await database.close()

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath))
    }

    func testExistingCanonicalDatabaseKeepsItsDataAndArchivesLegacyFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteLegacyIgnored.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyPath = directory.appendingPathComponent("marketsprite-v3.sqlite").path
        try SQLiteTestSupport.execute(legacySchemaSQL, atPath: legacyPath)
        try SQLiteTestSupport.execute(
            """
            INSERT INTO instruments VALUES ('us:AAPL', 'AAPL', '苹果', 'us');
            INSERT INTO watchlist_items VALUES ('us:AAPL', 0);
            """,
            atPath: legacyPath
        )

        // Pre-create the canonical database directly so it carries its seeded
        // defaults; the legacy database must then be fully ignored.
        let canonicalPath = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let first = try MarketDatabase.open(atPath: canonicalPath)
        try await first.close()

        // Canonical already exists: keep its data and archive the legacy database
        // without treating it as a migration source.
        let database = try MarketDatabase.openInDirectory(directory)
        let watchlist = try await database.loadWatchlist()
        XCTAssertEqual(watchlist, Instrument.initialWatchlist)
        try await database.close()

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath))
        let backupDirectory = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory.appendingPathComponent("Backups"),
                includingPropertiesForKeys: nil
            ).first
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupDirectory.appendingPathComponent("marketsprite-v3.sqlite").path
        ))
    }

    func testLegacyFilesAreArchivedWithoutAMigrationSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteLegacyArchiveOnly.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["marketsprite-v2.sqlite", "quotes.sqlite"] {
            try SQLiteTestSupport.execute(
                "CREATE TABLE junk (id INTEGER);",
                atPath: directory.appendingPathComponent(name).path
            )
        }

        let database = try MarketDatabase.openInDirectory(directory)
        let watchlist = try await database.loadWatchlist()
        XCTAssertEqual(watchlist, Instrument.initialWatchlist)
        try await database.close()

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(remaining, [MarketDatabase.defaultFileName, "Backups"])
        let backupDirectory = directory.appendingPathComponent("Backups").appendingPathComponent(
            try XCTUnwrap(FileManager.default.contentsOfDirectory(
                atPath: directory.appendingPathComponent("Backups").path
            ).first)
        )
        let archived = Set(try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path))
        XCTAssertEqual(archived, ["marketsprite-v2.sqlite", "quotes.sqlite"])
    }

    func testInvalidLegacyDatabaseBlocksStartupWithoutHalfWrittenMainDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteLegacyInvalid.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyPath = directory.appendingPathComponent("marketsprite-v3.sqlite").path
        try SQLiteTestSupport.execute(legacySchemaSQL, atPath: legacyPath)
        // Orphan watchlist entry makes the foreign-key check fail, so migration is rejected.
        try SQLiteTestSupport.execute(
            "INSERT INTO watchlist_items VALUES ('us:MISSING', 0);",
            atPath: legacyPath
        )

        XCTAssertThrowsError(try MarketDatabase.openInDirectory(directory))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPath))
    }

    func testLegacyMigrationArchivesAllLegacyVariantsAndSidecars() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpriteLegacyArchive.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try SQLiteTestSupport.execute(legacySchemaSQL, atPath: directory.appendingPathComponent("marketsprite-v3.sqlite").path)
        // Extra legacy variants observed in real Application Support folders.
        for extra in [
            "marketsprite-v2.sqlite",
            "marketsprite-v2.before-import-20260811.sqlite",
            "marketsprite-v3.before-watchlist-restore-20260811.sqlite",
            "marketsprite-v3.sqlite.pre-release-20260812",
            "quotes.sqlite",
            "quotes.sqlite-journal",
        ] {
            try SQLiteTestSupport.execute(
                "CREATE TABLE junk (id INTEGER);",
                atPath: directory.appendingPathComponent(extra).path
            )
        }

        _ = try MarketDatabase.openInDirectory(directory)

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(remaining, [MarketDatabase.defaultFileName, "Backups"])
        let backupDirectory = directory.appendingPathComponent("Backups").appendingPathComponent(
            try XCTUnwrap(FileManager.default.contentsOfDirectory(
                atPath: directory.appendingPathComponent("Backups").path
            ).first)
        )
        let archived = Set(try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path))
        for name in [
            "marketsprite-v2.sqlite",
            "marketsprite-v2.before-import-20260811.sqlite",
            "marketsprite-v3.before-watchlist-restore-20260811.sqlite",
            "marketsprite-v3.sqlite",
            "marketsprite-v3.sqlite.pre-release-20260812",
            "quotes.sqlite",
            "quotes.sqlite-journal",
        ] {
            XCTAssertTrue(archived.contains(name), "missing archived file \(name)")
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

    /// GRDB's Date storage format: "yyyy-MM-dd HH:mm:ss.SSS" in UTC.
    private var storageDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
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

    private var legacySchemaSQL: String {
        """
        PRAGMA user_version = 1;
        CREATE TABLE instruments (id TEXT PRIMARY KEY, symbol TEXT NOT NULL, name TEXT NOT NULL, namespace TEXT NOT NULL);
        CREATE TABLE watchlist_items (instrument_id TEXT PRIMARY KEY REFERENCES instruments(id) ON DELETE CASCADE, sort_order INTEGER NOT NULL UNIQUE);
        CREATE TABLE quote_sessions (instrument_id TEXT NOT NULL REFERENCES instruments(id) ON DELETE CASCADE, session_date TEXT NOT NULL, day_open DOUBLE NOT NULL, previous_close DOUBLE NOT NULL, last_price DOUBLE NOT NULL, market_time DATETIME NOT NULL, received_at DATETIME NOT NULL, source TEXT NOT NULL, PRIMARY KEY (instrument_id, session_date));
        CREATE TABLE minute_bars (instrument_id TEXT NOT NULL REFERENCES instruments(id) ON DELETE CASCADE, session_date TEXT NOT NULL, minute_at DATETIME NOT NULL, open DOUBLE NOT NULL, close DOUBLE NOT NULL, high DOUBLE NOT NULL, low DOUBLE NOT NULL, PRIMARY KEY (instrument_id, minute_at));
        CREATE TABLE alert_configuration (id INTEGER PRIMARY KEY, is_enabled BOOLEAN NOT NULL, basis TEXT NOT NULL, rising_threshold DOUBLE NOT NULL, falling_threshold DOUBLE NOT NULL);
        CREATE TABLE price_alert_targets (instrument_id TEXT PRIMARY KEY REFERENCES instruments(id) ON DELETE CASCADE, rising_price DOUBLE NOT NULL, falling_price DOUBLE NOT NULL);
        CREATE TABLE application_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
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
