import Foundation
import GRDB
import OSLog

actor MarketDatabase {
    static let defaultFileName = "marketsprite.sqlite"
    private static let legacyFileName = "marketsprite-v3.sqlite"
    private static let signposter = OSSignposter(
        subsystem: "io.github.cmy-hhxx.marketsprite",
        category: "Database"
    )

    private let databaseQueue: DatabaseQueue
    nonisolated let databasePath: String

    private init(
        databaseQueue: DatabaseQueue,
        databasePath: String,
        initialize: Bool = true
    ) throws {
        self.databaseQueue = databaseQueue
        self.databasePath = databasePath
        if initialize {
            try DatabaseSchema.initialize(databaseQueue)
        } else {
            try DatabaseSchema.validate(databaseQueue)
        }
    }

    static func inMemory() throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(configuration: configuration()),
            databasePath: ":memory:"
        )
    }

    static func open(atPath path: String) throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(path: path, configuration: configuration()),
            databasePath: path
        )
    }

    static func openReadOnly(atPath path: String) throws -> MarketDatabase {
        var readOnlyConfiguration = configuration()
        readOnlyConfiguration.readonly = true
        return try MarketDatabase(
            databaseQueue: DatabaseQueue(path: path, configuration: readOnlyConfiguration),
            databasePath: path,
            initialize: false
        )
    }

    static func openInApplicationSupport(
        appFolderName: String,
        fileName: String = defaultFileName,
        fileManager: FileManager = .default
    ) throws -> MarketDatabase {
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MarketDatabaseError.applicationSupportUnavailable
        }
        let folder = support.appendingPathComponent(appFolderName, isDirectory: true)
        return try openInDirectory(folder, fileName: fileName, fileManager: fileManager)
    }

    static func openInDirectory(
        _ folder: URL,
        fileName: String = defaultFileName,
        fileManager: FileManager = .default
    ) throws -> MarketDatabase {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let canonicalURL = folder.appendingPathComponent(fileName, isDirectory: false)
        let legacyURL = folder.appendingPathComponent(legacyFileName, isDirectory: false)

        if !fileManager.fileExists(atPath: canonicalURL.path),
           fileManager.fileExists(atPath: legacyURL.path) {
            try migrateLegacyDatabase(
                at: legacyURL,
                to: canonicalURL,
                folder: folder,
                fileManager: fileManager
            )
        }

        let database = try MarketDatabase(
            databaseQueue: DatabaseQueue(
                path: canonicalURL.path,
                configuration: configuration()
            ),
            databasePath: canonicalURL.path
        )
        try archiveLegacyFiles(
            from: folder,
            excluding: canonicalURL.lastPathComponent,
            fileManager: fileManager
        )
        return database
    }

    nonisolated static func applicationSupportDatabasePath(
        appFolderName: String,
        fileName: String = defaultFileName,
        fileManager: FileManager = .default
    ) -> String {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        return support?
            .appendingPathComponent(appFolderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
            .path ?? ""
    }

    func loadWatchlist() throws -> [Instrument] {
        try databaseQueue.read(Self.fetchWatchlist)
    }

    func replaceWatchlist(with instruments: [Instrument]) throws {
        let IDs = instruments.map(\.id)
        guard Set(IDs).count == instruments.count else {
            throw MarketDatabaseError.invalidWatchlist
        }

        try databaseQueue.write { database in
            let storedIDs = Set(try String.fetchAll(
                database,
                sql: "SELECT instrument_id FROM watchlist"
            ))
            let incomingIDs = Set(IDs.map(\.rawValue))

            for storedID in storedIDs.subtracting(incomingIDs) {
                try database.execute(
                    sql: "DELETE FROM watchlist WHERE instrument_id = ?",
                    arguments: [storedID]
                )
            }

            if !storedIDs.isEmpty {
                try database.execute(sql: "UPDATE watchlist SET position = position + 1000000")
            }

            for (position, instrument) in instruments.enumerated() {
                try database.execute(
                    sql: """
                    INSERT INTO watchlist (instrument_id, namespace, symbol, name, position)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(instrument_id) DO UPDATE SET
                        namespace = excluded.namespace,
                        symbol = excluded.symbol,
                        name = excluded.name,
                        position = excluded.position
                    """,
                    arguments: [
                        instrument.id.rawValue,
                        instrument.namespace.rawValue,
                        instrument.symbol,
                        instrument.name,
                        position,
                    ]
                )
            }
        }
    }

    @discardableResult
    func saveQuote(_ snapshot: QuoteSnapshot, for instrument: Instrument) throws -> Bool {
        let interval = Self.signposter.beginInterval(
            "SynchronizeQuoteSnapshot",
            id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("SynchronizeQuoteSnapshot", interval) }

        guard snapshot.instrumentID == instrument.id else {
            throw MarketDatabaseError.quoteInstrumentMismatch(
                expected: instrument.id,
                actual: snapshot.instrumentID
            )
        }
        let sessionDate = TradingCalendar.sessionDate(
            for: snapshot.marketTime,
            market: instrument.market
        )
        try Self.validate(snapshot, for: instrument, sessionDate: sessionDate)

        return try databaseQueue.write { database in
            let isObserved = try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS(SELECT 1 FROM watchlist WHERE instrument_id = ?)",
                arguments: [instrument.id.rawValue]
            ) ?? false
            guard isObserved else { return false }

            let storedSessionDate = try String.fetchOne(
                database,
                sql: "SELECT session_date FROM quote_cache WHERE instrument_id = ?",
                arguments: [instrument.id.rawValue]
            )
            if storedSessionDate != nil, storedSessionDate != sessionDate {
                try database.execute(
                    sql: "DELETE FROM quote_cache WHERE instrument_id = ?",
                    arguments: [instrument.id.rawValue]
                )
            }

            try database.execute(
                sql: """
                INSERT INTO quote_cache (
                    instrument_id, session_date, day_open, previous_close, last_price,
                    quoted_at_ms, received_at_ms, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(instrument_id) DO UPDATE SET
                    session_date = excluded.session_date,
                    day_open = excluded.day_open,
                    previous_close = excluded.previous_close,
                    last_price = excluded.last_price,
                    quoted_at_ms = excluded.quoted_at_ms,
                    received_at_ms = excluded.received_at_ms,
                    source = excluded.source
                """,
                arguments: [
                    instrument.id.rawValue,
                    sessionDate,
                    snapshot.dayOpen,
                    snapshot.previousClose,
                    snapshot.lastPrice,
                    Self.milliseconds(snapshot.marketTime),
                    Self.milliseconds(snapshot.receivedAt),
                    Self.sourceValue(snapshot.source),
                ]
            )

            let storedRows = try Row.fetchAll(
                database,
                sql: """
                SELECT minute_at_ms, open, close, high, low
                FROM minute_bars
                WHERE instrument_id = ?
                """,
                arguments: [instrument.id.rawValue]
            )
            let storedBars = Dictionary(uniqueKeysWithValues: storedRows.map { row in
                let time: Int64 = row["minute_at_ms"]
                return (
                    time,
                    MinuteBar(
                        time: Self.date(fromMilliseconds: time),
                        open: row["open"],
                        close: row["close"],
                        high: row["high"],
                        low: row["low"]
                    )
                )
            })
            let incomingTimes = Set(snapshot.minuteBars.map { Self.milliseconds($0.time) })
            for storedTime in storedBars.keys where !incomingTimes.contains(storedTime) {
                try database.execute(
                    sql: "DELETE FROM minute_bars WHERE instrument_id = ? AND minute_at_ms = ?",
                    arguments: [instrument.id.rawValue, storedTime]
                )
            }
            for bar in snapshot.minuteBars {
                let minuteAt = Self.milliseconds(bar.time)
                guard storedBars[minuteAt] != bar else { continue }
                try database.execute(
                    sql: """
                    INSERT INTO minute_bars (
                        instrument_id, minute_at_ms, open, close, high, low
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(instrument_id, minute_at_ms) DO UPDATE SET
                        open = excluded.open,
                        close = excluded.close,
                        high = excluded.high,
                        low = excluded.low
                    """,
                    arguments: [
                        instrument.id.rawValue,
                        minuteAt,
                        bar.open,
                        bar.close,
                        bar.high,
                        bar.low,
                    ]
                )
            }
            return true
        }
    }

    func loadLatestQuotes(for instruments: [Instrument]) throws -> [InstrumentID: QuoteSnapshot] {
        try databaseQueue.read { database in
            var snapshots: [InstrumentID: QuoteSnapshot] = [:]
            for instrument in instruments {
                guard let session = try Row.fetchOne(
                    database,
                    sql: """
                    SELECT session_date, day_open, previous_close, last_price,
                           quoted_at_ms, received_at_ms, source
                    FROM quote_cache WHERE instrument_id = ?
                    """,
                    arguments: [instrument.id.rawValue]
                ) else { continue }
                let source: QuoteSource = try Self.quoteSource(from: session["source"])
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT minute_at_ms, open, close, high, low
                    FROM minute_bars WHERE instrument_id = ?
                    ORDER BY minute_at_ms
                    """,
                    arguments: [instrument.id.rawValue]
                )
                let bars = rows.map { row in
                    let time: Int64 = row["minute_at_ms"]
                    return MinuteBar(
                        time: Self.date(fromMilliseconds: time),
                        open: row["open"],
                        close: row["close"],
                        high: row["high"],
                        low: row["low"]
                    )
                }
                let quotedAt: Int64 = session["quoted_at_ms"]
                let receivedAt: Int64 = session["received_at_ms"]
                snapshots[instrument.id] = QuoteSnapshot(
                    instrumentID: instrument.id,
                    minuteBars: bars,
                    dayOpen: session["day_open"],
                    previousClose: session["previous_close"],
                    lastPrice: session["last_price"],
                    marketTime: Self.date(fromMilliseconds: quotedAt),
                    receivedAt: Self.date(fromMilliseconds: receivedAt),
                    source: source
                )
            }
            return snapshots
        }
    }

    func quoteBarCount() throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM minute_bars") ?? 0
        }
    }

    func clearQuotes() throws {
        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM quote_cache")
        }
    }

    func close() throws {
        try databaseQueue.close()
    }

    func loadAlertSettings() throws -> AlertSettingsSnapshot {
        try databaseQueue.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT enabled, basis, rising_percent, falling_percent
                FROM alert_settings WHERE singleton = 1
                """
            ) else {
                throw MarketDatabaseError.invalidAlertConfiguration
            }
            let basisValue: String = row["basis"]
            let basis = try Self.alertBasis(from: basisValue)
            let configuration = AlertConfiguration(
                isEnabled: row["enabled"],
                basis: basis,
                risingThreshold: row["rising_percent"],
                fallingThreshold: row["falling_percent"]
            )
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT instrument_id, rising_price, falling_price FROM price_alerts"
            )
            let targets = try rows.reduce(into: [InstrumentID: PriceAlertTargets]()) { result, row in
                let storedID: String = row["instrument_id"]
                let id = try InstrumentID(validatingRawValue: storedID)
                result[id] = PriceAlertTargets(
                    risingPrice: row["rising_price"],
                    fallingPrice: row["falling_price"]
                )
            }
            return AlertSettingsSnapshot(configuration: configuration, priceTargets: targets)
        }
    }

    func saveAlertSettings(_ snapshot: AlertSettingsSnapshot) throws {
        try Self.validate(snapshot.configuration)
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                UPDATE alert_settings SET
                    enabled = ?, basis = ?, rising_percent = ?, falling_percent = ?
                WHERE singleton = 1
                """,
                arguments: [
                    snapshot.configuration.isEnabled,
                    Self.alertBasisValue(snapshot.configuration.basis),
                    snapshot.configuration.risingThreshold,
                    snapshot.configuration.fallingThreshold,
                ]
            )
            try database.execute(sql: "DELETE FROM price_alerts")
            for (instrumentID, target) in snapshot.priceTargets where target.isEnabled {
                try database.execute(
                    sql: """
                    INSERT INTO price_alerts (instrument_id, rising_price, falling_price)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [
                        instrumentID.rawValue,
                        target.risingPrice,
                        target.fallingPrice,
                    ]
                )
            }
        }
    }

    private static func validate(_ configuration: AlertConfiguration) throws {
        guard configuration.risingThreshold.isFinite,
              configuration.fallingThreshold.isFinite,
              (0.5...15).contains(configuration.risingThreshold),
              (0.5...15).contains(configuration.fallingThreshold)
        else {
            throw MarketDatabaseError.invalidAlertConfiguration
        }
    }

    private static func validate(
        _ snapshot: QuoteSnapshot,
        for instrument: Instrument,
        sessionDate: String
    ) throws {
        let quoteValues = [snapshot.dayOpen, snapshot.previousClose, snapshot.lastPrice]
        guard quoteValues.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw MarketDatabaseError.invalidQuote(tr("开盘价、昨收价和最新价必须为正数"))
        }
        guard snapshot.marketTime.timeIntervalSinceReferenceDate.isFinite,
              snapshot.receivedAt.timeIntervalSinceReferenceDate.isFinite,
              Self.milliseconds(snapshot.marketTime) > 0,
              Self.milliseconds(snapshot.receivedAt) > 0
        else {
            throw MarketDatabaseError.invalidQuote(tr("行情时间无效"))
        }
        var previousTime: Date?
        for bar in snapshot.minuteBars {
            if let previousTime, bar.time <= previousTime {
                throw MarketDatabaseError.invalidQuote(tr("分钟线时间必须严格递增且不能重复"))
            }
            let values = [bar.open, bar.close, bar.high, bar.low]
            guard values.allSatisfy({ $0.isFinite && $0 > 0 }),
                  bar.high >= max(bar.open, bar.close),
                  bar.low <= min(bar.open, bar.close)
            else {
                throw MarketDatabaseError.invalidQuote(tr("分钟线 OHLC 数据无效"))
            }
            guard TradingCalendar.sessionDate(for: bar.time, market: instrument.market) == sessionDate else {
                throw MarketDatabaseError.invalidQuote(tr("分钟线不属于行情交易日"))
            }
            previousTime = bar.time
        }
    }

    private static func fetchWatchlist(from database: Database) throws -> [Instrument] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT instrument_id, symbol, name, namespace, position
            FROM watchlist ORDER BY position
            """
        )
        return try rows.enumerated().map { index, row in
            let storedID: String = row["instrument_id"]
            let namespaceValue: String = row["namespace"]
            guard let namespace = SymbolNamespace(rawValue: namespaceValue) else {
                throw MarketDatabaseError.invalidNamespace(namespaceValue)
            }
            let instrument = try Instrument(
                validatingSymbol: row["symbol"],
                name: row["name"],
                namespace: namespace
            )
            guard instrument.id.rawValue == storedID else {
                throw MarketDatabaseError.invalidInstrumentID(
                    expected: instrument.id,
                    stored: storedID
                )
            }
            let position: Int = row["position"]
            guard position == index else { throw MarketDatabaseError.invalidWatchlist }
            return instrument
        }
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        return configuration
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func sourceValue(_ source: QuoteSource) -> String {
        switch source {
        case .tencent: "tencent"
        case .eastMoney: "east_money"
        }
    }

    private static func quoteSource(from value: String) throws -> QuoteSource {
        switch value {
        case "tencent": .tencent
        case "east_money": .eastMoney
        default: throw MarketDatabaseError.invalidQuoteSource(value)
        }
    }

    private static func alertBasisValue(_ basis: AlertBasis) -> String {
        switch basis {
        case .percentage: "percentage"
        case .targetPrice: "target_price"
        }
    }

    private static func alertBasis(from value: String) throws -> AlertBasis {
        switch value {
        case "percentage": .percentage
        case "target_price": .targetPrice
        default: throw MarketDatabaseError.invalidAlertBasis(value)
        }
    }
}

private extension MarketDatabase {
    struct LegacySnapshot {
        let instrument: Instrument
        let snapshot: QuoteSnapshot
    }

    static func migrateLegacyDatabase(
        at legacyURL: URL,
        to canonicalURL: URL,
        folder: URL,
        fileManager: FileManager
    ) throws {
        let legacy = try DatabaseQueue(
            path: legacyURL.path,
            configuration: legacyConfiguration()
        )
        let payload = try legacy.read(readLegacyDatabase)
        try legacy.close()

        let temporaryURL = folder.appendingPathComponent(
            ".marketsprite.sqlite.migrating-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let replacement = try DatabaseQueue(path: temporaryURL.path, configuration: configuration())
        try DatabaseSchema.initialize(replacement)
        try replacement.write { database in
            try database.execute(sql: "DELETE FROM watchlist")
            for (position, instrument) in payload.instruments.enumerated() {
                try database.execute(
                    sql: """
                    INSERT INTO watchlist (instrument_id, namespace, symbol, name, position)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        instrument.id.rawValue,
                        instrument.namespace.rawValue,
                        instrument.symbol,
                        instrument.name,
                        position,
                    ]
                )
            }
            try database.execute(
                sql: """
                UPDATE alert_settings SET
                    enabled = ?, basis = ?, rising_percent = ?, falling_percent = ?
                WHERE singleton = 1
                """,
                arguments: [
                    payload.alertSettings.configuration.isEnabled,
                    Self.alertBasisValue(payload.alertSettings.configuration.basis),
                    payload.alertSettings.configuration.risingThreshold,
                    payload.alertSettings.configuration.fallingThreshold,
                ]
            )
            for (instrumentID, target) in payload.alertSettings.priceTargets where target.isEnabled {
                try database.execute(
                    sql: """
                    INSERT INTO price_alerts (instrument_id, rising_price, falling_price)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [instrumentID.rawValue, target.risingPrice, target.fallingPrice]
                )
            }
            for entry in payload.snapshots {
                let snapshot = entry.snapshot
                try database.execute(
                    sql: """
                    INSERT INTO quote_cache (
                        instrument_id, session_date, day_open, previous_close, last_price,
                        quoted_at_ms, received_at_ms, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        entry.instrument.id.rawValue,
                        TradingCalendar.sessionDate(
                            for: snapshot.marketTime,
                            market: entry.instrument.market
                        ),
                        snapshot.dayOpen,
                        snapshot.previousClose,
                        snapshot.lastPrice,
                        milliseconds(snapshot.marketTime),
                        milliseconds(snapshot.receivedAt),
                        sourceValue(snapshot.source),
                    ]
                )
                for bar in snapshot.minuteBars {
                    try database.execute(
                        sql: """
                        INSERT INTO minute_bars (
                            instrument_id, minute_at_ms, open, close, high, low
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            entry.instrument.id.rawValue,
                            milliseconds(bar.time),
                            bar.open,
                            bar.close,
                            bar.high,
                            bar.low,
                        ]
                    )
                }
            }
        }
        let isValid = try replacement.read { database in
            try DatabaseSchema.validate(database)
            let instruments = try fetchWatchlist(from: database)
            let alertCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM price_alerts") ?? 0
            let quoteCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM quote_cache") ?? 0
            let barCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM minute_bars") ?? 0
            return instruments == payload.instruments
                && alertCount == payload.alertSettings.priceTargets.count
                && quoteCount == payload.snapshots.count
                && barCount == payload.snapshots.reduce(0) { $0 + $1.snapshot.minuteBars.count }
        }
        try replacement.close()

        guard isValid else {
            throw MarketDatabaseError.legacyDatabaseInvalid
        }

        try fileManager.moveItem(at: temporaryURL, to: canonicalURL)
    }

    static func legacyConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }

    static func archiveLegacyFiles(
        from folder: URL,
        excluding activeFileName: String,
        fileManager: FileManager
    ) throws {
        let names = try fileManager.contentsOfDirectory(atPath: folder.path)
        let prefixes = ["marketsprite-v2", "marketsprite-v3", "quotes.sqlite"]
        let candidates = names.filter { candidate in
            candidate != activeFileName
                && prefixes.contains(where: { candidate.hasPrefix($0) })
        }.sorted()
        guard !candidates.isEmpty else { return }

        let backups = folder.appendingPathComponent("Backups", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
        ]
        let backup = backups.appendingPathComponent(
            "legacy-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))",
            isDirectory: true
        )
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)

        for candidate in candidates {
            let source = folder.appendingPathComponent(candidate)
            let destination = backup.appendingPathComponent(candidate)
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    static func readLegacyDatabase(_ database: Database) throws -> (
        instruments: [Instrument],
        alertSettings: AlertSettingsSnapshot,
        snapshots: [LegacySnapshot]
    ) {
        let version = try Int.fetchOne(database, sql: "PRAGMA user_version") ?? 0
        guard version == 1,
              try String.fetchOne(database, sql: "PRAGMA quick_check") == "ok",
              try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty
        else { throw MarketDatabaseError.legacyDatabaseInvalid }

        let instruments = try Row.fetchAll(
            database,
            sql: """
            SELECT instruments.id, instruments.symbol, instruments.name, instruments.namespace
            FROM watchlist_items
            JOIN instruments ON instruments.id = watchlist_items.instrument_id
            ORDER BY watchlist_items.sort_order
            """
        ).map(legacyInstrument)

        let configuration: AlertConfiguration
        if let row = try Row.fetchOne(
            database,
            sql: """
            SELECT is_enabled, basis, rising_threshold, falling_threshold
            FROM alert_configuration WHERE id = 1
            """
        ) {
            let basisValue: String = row["basis"]
            guard let basis = AlertBasis(rawValue: basisValue) else {
                throw MarketDatabaseError.legacyDatabaseInvalid
            }
            configuration = AlertConfiguration(
                isEnabled: row["is_enabled"],
                basis: basis,
                risingThreshold: row["rising_threshold"],
                fallingThreshold: row["falling_threshold"]
            )
        } else {
            configuration = .default
        }
        try validate(configuration)

        let targetRows = try Row.fetchAll(
            database,
            sql: "SELECT instrument_id, rising_price, falling_price FROM price_alert_targets"
        )
        let observedIDs = Set(instruments.map(\.id))
        let targets = try targetRows.reduce(into: [InstrumentID: PriceAlertTargets]()) { result, row in
            let id = try InstrumentID(validatingRawValue: row["instrument_id"])
            guard observedIDs.contains(id) else { return }
            let rising: Double = row["rising_price"]
            let falling: Double = row["falling_price"]
            let target = PriceAlertTargets(
                risingPrice: rising > 0 ? rising : nil,
                fallingPrice: falling > 0 ? falling : nil
            )
            if target.isEnabled { result[id] = target }
        }

        let latestSessions = try instruments.compactMap { instrument -> LegacySnapshot? in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT session_date, day_open, previous_close, last_price,
                       market_time, received_at, source
                FROM quote_sessions
                WHERE instrument_id = ?
                ORDER BY market_time DESC LIMIT 1
                """,
                arguments: [instrument.id.rawValue]
            ) else { return nil }
            let sourceRaw: String = row["source"]
            let source: QuoteSource
            switch sourceRaw {
            case "tencent": source = .tencent
            case "eastMoney": source = .eastMoney
            default: throw MarketDatabaseError.legacyDatabaseInvalid
            }
            let sessionDate: String = row["session_date"]
            let minuteRows = try Row.fetchAll(
                database,
                sql: """
                SELECT minute_at, open, close, high, low
                FROM minute_bars
                WHERE instrument_id = ? AND session_date = ?
                ORDER BY minute_at
                """,
                arguments: [instrument.id.rawValue, sessionDate]
            )
            let bars = minuteRows.map { row in
                MinuteBar(
                    time: row["minute_at"],
                    open: row["open"],
                    close: row["close"],
                    high: row["high"],
                    low: row["low"]
                )
            }
            let snapshot = QuoteSnapshot(
                instrumentID: instrument.id,
                minuteBars: bars,
                dayOpen: row["day_open"],
                previousClose: row["previous_close"],
                lastPrice: row["last_price"],
                marketTime: row["market_time"],
                receivedAt: row["received_at"],
                source: source
            )
            try validate(snapshot, for: instrument, sessionDate: sessionDate)
            return LegacySnapshot(instrument: instrument, snapshot: snapshot)
        }
        return (
            instruments,
            AlertSettingsSnapshot(configuration: configuration, priceTargets: targets),
            latestSessions
        )
    }

    static func legacyInstrument(_ row: Row) throws -> Instrument {
        let namespaceValue: String = row["namespace"]
        guard let namespace = SymbolNamespace(rawValue: namespaceValue) else {
            throw MarketDatabaseError.legacyDatabaseInvalid
        }
        let instrument = try Instrument(
            validatingSymbol: row["symbol"],
            name: row["name"],
            namespace: namespace
        )
        let storedID: String = row["id"]
        guard instrument.id.rawValue == storedID else {
            throw MarketDatabaseError.legacyDatabaseInvalid
        }
        return instrument
    }
}
