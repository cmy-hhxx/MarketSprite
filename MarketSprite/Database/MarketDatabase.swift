import Foundation
import GRDB
import OSLog

actor MarketDatabase {
    static let defaultFileName = "marketsprite-v3.sqlite"
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
            databaseQueue: DatabaseQueue(
                path: path,
                configuration: readOnlyConfiguration
            ),
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
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName, isDirectory: false)

        return try MarketDatabase(
            databaseQueue: DatabaseQueue(path: url.path, configuration: configuration()),
            databasePath: url.path
        )
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
        try databaseQueue.read { database in
            try Self.fetchWatchlist(from: database)
        }
    }

    func loadWatchlist(defaultingTo defaults: [Instrument]) throws -> [Instrument] {
        try databaseQueue.write { database in
            let isInitialized = try String.fetchOne(
                database,
                sql: """
                SELECT value FROM application_metadata
                WHERE key = 'watchlist.initialized'
                """
            ) == "true"

            if !isInitialized {
                for (index, instrument) in defaults.enumerated() {
                    try Self.upsert(instrument, in: database)
                    try database.execute(
                        sql: """
                        INSERT INTO watchlist_items (instrument_id, sort_order)
                        VALUES (?, ?)
                        """,
                        arguments: [instrument.id.rawValue, index]
                    )
                }
                try Self.markWatchlistInitialized(in: database)
            }

            return try Self.fetchWatchlist(from: database)
        }
    }

    func replaceWatchlist(with instruments: [Instrument]) throws {
        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM watchlist_items")

            for (index, instrument) in instruments.enumerated() {
                try Self.upsert(instrument, in: database)
                try database.execute(
                    sql: """
                    INSERT INTO watchlist_items (instrument_id, sort_order)
                    VALUES (?, ?)
                    """,
                    arguments: [instrument.id.rawValue, index]
                )
            }
            try Self.markWatchlistInitialized(in: database)
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
                sql: "SELECT EXISTS(SELECT 1 FROM watchlist_items WHERE instrument_id = ?)",
                arguments: [instrument.id.rawValue]
            ) ?? false
            guard isObserved else { return false }

            try Self.upsert(instrument, in: database)
            let storedRows = try Row.fetchAll(
                database,
                sql: """
                SELECT minute_at, open, close, high, low
                FROM minute_bars
                WHERE instrument_id = ? AND session_date = ?
                """,
                arguments: [snapshot.instrumentID.rawValue, sessionDate]
            )
            let storedBars = Dictionary(
                uniqueKeysWithValues: storedRows.map { row in
                    let bar = MinuteBar(
                        time: row["minute_at"],
                        open: row["open"],
                        close: row["close"],
                        high: row["high"],
                        low: row["low"]
                    )
                    return (bar.time, bar)
                }
            )
            let incomingTimes = Set(snapshot.minuteBars.map(\.time))
            for storedTime in storedBars.keys where !incomingTimes.contains(storedTime) {
                try database.execute(
                    sql: """
                    DELETE FROM minute_bars
                    WHERE instrument_id = ? AND minute_at = ?
                    """,
                    arguments: [snapshot.instrumentID.rawValue, storedTime]
                )
            }

            for bar in snapshot.minuteBars where storedBars[bar.time] != bar {
                try database.execute(
                    sql: """
                    INSERT INTO minute_bars (
                        instrument_id, session_date, minute_at,
                        open, close, high, low
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(instrument_id, minute_at) DO UPDATE SET
                        session_date = excluded.session_date,
                        open = excluded.open,
                        close = excluded.close,
                        high = excluded.high,
                        low = excluded.low
                    """,
                    arguments: [
                        snapshot.instrumentID.rawValue,
                        sessionDate,
                        bar.time,
                        bar.open,
                        bar.close,
                        bar.high,
                        bar.low,
                    ]
                )
            }

            try database.execute(
                sql: """
                INSERT INTO quote_sessions (
                    instrument_id, session_date, day_open, previous_close,
                    last_price, market_time, received_at, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(instrument_id, session_date) DO UPDATE SET
                    day_open = excluded.day_open,
                    previous_close = excluded.previous_close,
                    last_price = excluded.last_price,
                    market_time = excluded.market_time,
                    received_at = excluded.received_at,
                    source = excluded.source
                """,
                arguments: [
                    snapshot.instrumentID.rawValue,
                    sessionDate,
                    snapshot.dayOpen,
                    snapshot.previousClose,
                    snapshot.lastPrice,
                    snapshot.marketTime,
                    snapshot.receivedAt,
                    snapshot.source.rawValue,
                ]
            )
            return true
        }
    }

    func loadLatestQuotes(
        for instruments: [Instrument]
    ) throws -> [InstrumentID: QuoteSnapshot] {
        try databaseQueue.read { database in
            var snapshots: [InstrumentID: QuoteSnapshot] = [:]

            for instrument in instruments {
                guard let session = try Row.fetchOne(
                    database,
                    sql: """
                    SELECT session_date, day_open, previous_close, last_price,
                           market_time, received_at, source
                    FROM quote_sessions
                    WHERE instrument_id = ?
                    ORDER BY market_time DESC
                    LIMIT 1
                    """,
                    arguments: [instrument.id.rawValue]
                ) else { continue }

                let sourceValue: String = session["source"]
                guard let source = QuoteSource(rawValue: sourceValue) else {
                    throw MarketDatabaseError.invalidQuoteSource(sourceValue)
                }
                let sessionDate: String = session["session_date"]
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT minute_at, open, close, high, low
                    FROM minute_bars
                    WHERE instrument_id = ? AND session_date = ?
                    ORDER BY minute_at
                    """,
                    arguments: [instrument.id.rawValue, sessionDate]
                )
                let bars = rows.map { row in
                    MinuteBar(
                        time: row["minute_at"],
                        open: row["open"],
                        close: row["close"],
                        high: row["high"],
                        low: row["low"]
                    )
                }

                snapshots[instrument.id] = QuoteSnapshot(
                    instrumentID: instrument.id,
                    minuteBars: bars,
                    dayOpen: session["day_open"],
                    previousClose: session["previous_close"],
                    lastPrice: session["last_price"],
                    marketTime: session["market_time"],
                    receivedAt: session["received_at"],
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
            try database.execute(sql: "DELETE FROM minute_bars")
            try database.execute(sql: "DELETE FROM quote_sessions")
        }
    }

    func close() throws {
        try databaseQueue.close()
    }

    func loadAlertSettings(for instruments: [Instrument]) throws -> AlertSettingsSnapshot {
        let includedIDs = Set(instruments.map(\.id))
        return try databaseQueue.read { database in
            let configuration: AlertConfiguration
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT is_enabled, basis, rising_threshold, falling_threshold
                FROM alert_configuration
                WHERE id = 1
                """
            ) else {
                configuration = .default
                return try AlertSettingsSnapshot(
                    configuration: configuration,
                    priceTargets: Self.fetchPriceAlertTargets(
                        from: database,
                        includedIDs: includedIDs
                    )
                )
            }
            let basisValue: String = row["basis"]
            guard let basis = AlertBasis(rawValue: basisValue) else {
                throw MarketDatabaseError.invalidAlertBasis(basisValue)
            }
            configuration = AlertConfiguration(
                isEnabled: row["is_enabled"],
                basis: basis,
                risingThreshold: row["rising_threshold"],
                fallingThreshold: row["falling_threshold"]
            )
            return try AlertSettingsSnapshot(
                configuration: configuration,
                priceTargets: Self.fetchPriceAlertTargets(
                    from: database,
                    includedIDs: includedIDs
                )
            )
        }
    }

    func saveAlertSettings(_ snapshot: AlertSettingsSnapshot) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO alert_configuration (
                    id, is_enabled, basis, rising_threshold, falling_threshold
                ) VALUES (1, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    is_enabled = excluded.is_enabled,
                    basis = excluded.basis,
                    rising_threshold = excluded.rising_threshold,
                    falling_threshold = excluded.falling_threshold
                """,
                arguments: [
                    snapshot.configuration.isEnabled,
                    snapshot.configuration.basis.rawValue,
                    snapshot.configuration.risingThreshold,
                    snapshot.configuration.fallingThreshold,
                ]
            )
            try database.execute(sql: "DELETE FROM price_alert_targets")
            for (instrumentID, target) in snapshot.priceTargets where target.isEnabled {
                try database.execute(
                    sql: """
                    INSERT INTO price_alert_targets (
                        instrument_id, rising_price, falling_price
                    ) VALUES (?, ?, ?)
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

    private static func upsert(_ instrument: Instrument, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO instruments (id, symbol, name, namespace)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                symbol = excluded.symbol,
                name = excluded.name,
                namespace = excluded.namespace
            """,
            arguments: [
                instrument.id.rawValue,
                instrument.symbol,
                instrument.name,
                instrument.namespace.rawValue,
            ]
        )
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
              snapshot.receivedAt.timeIntervalSinceReferenceDate.isFinite
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
                  bar.high >= max(bar.open, bar.close, bar.low),
                  bar.low <= min(bar.open, bar.close, bar.high)
            else {
                throw MarketDatabaseError.invalidQuote(tr("分钟线 OHLC 数据无效"))
            }
            guard TradingCalendar.sessionDate(for: bar.time, market: instrument.market)
                    == sessionDate
            else {
                throw MarketDatabaseError.invalidQuote(tr("分钟线不属于行情交易日"))
            }
            previousTime = bar.time
        }
    }

    private static func fetchPriceAlertTargets(
        from database: Database,
        includedIDs: Set<InstrumentID>
    ) throws -> [InstrumentID: PriceAlertTargets] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT instrument_id, rising_price, falling_price
            FROM price_alert_targets
            """
        )
        return try rows.reduce(into: [:]) { targets, row in
            let storedID: String = row["instrument_id"]
            let id = try InstrumentID(validatingRawValue: storedID)
            guard includedIDs.contains(id) else { return }
            targets[id] = PriceAlertTargets(
                risingPrice: row["rising_price"],
                fallingPrice: row["falling_price"]
            )
        }
    }

    private static func fetchWatchlist(from database: Database) throws -> [Instrument] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT instruments.id, instruments.symbol, instruments.name, instruments.namespace
            FROM watchlist_items
            JOIN instruments ON instruments.id = watchlist_items.instrument_id
            ORDER BY watchlist_items.sort_order
            """
        )

        return try rows.map { row in
            let storedID: String = row["id"]
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
            return instrument
        }
    }

    private static func markWatchlistInitialized(in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO application_metadata (key, value)
            VALUES ('watchlist.initialized', 'true')
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """
        )
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }
}
