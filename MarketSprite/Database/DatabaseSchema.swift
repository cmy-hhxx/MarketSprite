import GRDB

enum DatabaseSchema {
    static let version = 2
    static let applicationID = 0x4D535052

    static func initialize(_ writer: any DatabaseWriter) throws {
        try writer.write { database in
            let version = try currentVersion(in: database)
        let storedApplicationID = try currentApplicationID(in: database)

            if version == 0, storedApplicationID == 0, try isEmpty(database) {
                try createCurrentSchema(in: database)
                try database.execute(sql: "PRAGMA application_id = \(self.applicationID)")
                try database.execute(sql: "PRAGMA user_version = \(self.version)")
            } else {
                try validate(database)
            }
        }
    }

    static func validate(_ reader: any DatabaseReader) throws {
        try reader.read(validate)
    }

    static func validate(_ database: Database) throws {
        let applicationID = try currentApplicationID(in: database)
        guard applicationID == self.applicationID else {
            throw MarketDatabaseError.unrecognizedDatabase(applicationID)
        }

        let version = try currentVersion(in: database)
        guard version == self.version else {
            throw MarketDatabaseError.unsupportedSchemaVersion(version)
        }

        guard try String.fetchOne(database, sql: "PRAGMA quick_check") == "ok" else {
            throw MarketDatabaseError.integrityCheckFailed
        }
        guard try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty else {
            throw MarketDatabaseError.integrityCheckFailed
        }
    }

    private static func currentVersion(in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: "PRAGMA user_version") ?? 0
    }

    private static func currentApplicationID(in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: "PRAGMA application_id") ?? 0
    }

    private static func isEmpty(_ database: Database) throws -> Bool {
        try String.fetchOne(
            database,
            sql: "SELECT name FROM sqlite_schema WHERE type = 'table' LIMIT 1"
        ) == nil
    }

    private static func createCurrentSchema(in database: Database) throws {
        try database.execute(sql: """
        CREATE TABLE watchlist (
            instrument_id TEXT NOT NULL PRIMARY KEY,
            namespace TEXT NOT NULL CHECK(namespace IN ('sse', 'szse', 'bse', 'hk', 'us')),
            symbol TEXT NOT NULL,
            name TEXT NOT NULL CHECK(
                length(name) BETWEEN 1 AND 128
                AND name = trim(name)
                AND instr(name, ':') = 0
            ),
            position INTEGER NOT NULL UNIQUE CHECK(position >= 0),
            CHECK(instrument_id = namespace || ':' || symbol),
            CHECK(
                (namespace IN ('sse', 'szse', 'bse')
                    AND length(symbol) = 6
                    AND symbol NOT GLOB '*[^0-9]*')
                OR (namespace = 'hk'
                    AND length(symbol) = 5
                    AND symbol NOT GLOB '*[^0-9]*')
                OR (namespace = 'us'
                    AND length(symbol) BETWEEN 1 AND 16
                    AND symbol NOT GLOB '*[^A-Z0-9.-]*')
            )
        ) STRICT, WITHOUT ROWID;
        """)

        try database.execute(sql: """
        CREATE TABLE alert_settings (
            singleton INTEGER NOT NULL PRIMARY KEY CHECK(singleton = 1),
            enabled INTEGER NOT NULL CHECK(enabled IN (0, 1)),
            basis TEXT NOT NULL CHECK(basis IN ('percentage', 'target_price')),
            rising_percent REAL NOT NULL CHECK(rising_percent BETWEEN 0.5 AND 15.0),
            falling_percent REAL NOT NULL CHECK(falling_percent BETWEEN 0.5 AND 15.0)
        ) STRICT, WITHOUT ROWID;
        """)

        try database.execute(sql: """
        CREATE TABLE price_alerts (
            instrument_id TEXT NOT NULL PRIMARY KEY
                REFERENCES watchlist(instrument_id) ON DELETE CASCADE,
            rising_price REAL CHECK(rising_price > 0),
            falling_price REAL CHECK(falling_price > 0),
            CHECK(rising_price IS NOT NULL OR falling_price IS NOT NULL)
        ) STRICT, WITHOUT ROWID;
        """)

        try database.execute(sql: """
        CREATE TABLE quote_cache (
            instrument_id TEXT NOT NULL PRIMARY KEY
                REFERENCES watchlist(instrument_id) ON DELETE CASCADE,
            session_date TEXT NOT NULL CHECK(
                session_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
            ),
            day_open REAL NOT NULL CHECK(day_open > 0),
            previous_close REAL NOT NULL CHECK(previous_close > 0),
            last_price REAL NOT NULL CHECK(last_price > 0),
            quoted_at_ms INTEGER NOT NULL CHECK(quoted_at_ms > 0),
            received_at_ms INTEGER NOT NULL CHECK(received_at_ms > 0),
            source TEXT NOT NULL CHECK(source IN ('tencent', 'east_money'))
        ) STRICT, WITHOUT ROWID;
        """)

        try database.execute(sql: """
        CREATE TABLE minute_bars (
            instrument_id TEXT NOT NULL
                REFERENCES quote_cache(instrument_id) ON DELETE CASCADE,
            minute_at_ms INTEGER NOT NULL CHECK(minute_at_ms > 0),
            open REAL NOT NULL CHECK(open > 0),
            close REAL NOT NULL CHECK(close > 0),
            high REAL NOT NULL CHECK(high >= open AND high >= close),
            low REAL NOT NULL CHECK(low <= open AND low <= close),
            CHECK(low <= high),
            PRIMARY KEY(instrument_id, minute_at_ms)
        ) STRICT, WITHOUT ROWID;
        """)

        let defaults = Instrument.initialWatchlist
        for (position, instrument) in defaults.enumerated() {
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
            INSERT INTO alert_settings (
                singleton, enabled, basis, rising_percent, falling_percent
            ) VALUES (1, 1, 'percentage', 3.0, 3.0)
            """
        )
    }
}
