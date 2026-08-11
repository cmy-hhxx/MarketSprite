import GRDB

enum DatabaseSchema {
    static let version = 1

    static func initialize(_ writer: any DatabaseWriter) throws {
        try writer.write { database in
            let storedVersion = try currentVersion(in: database)
            switch storedVersion {
            case 0:
                try createCurrentSchema(in: database)
                try database.execute(sql: "PRAGMA user_version = \(version)")
            case version:
                break
            default:
                throw MarketDatabaseError.unsupportedSchemaVersion(storedVersion)
            }
        }
    }

    static func validate(_ reader: any DatabaseReader) throws {
        try reader.read { database in
            let storedVersion = try currentVersion(in: database)
            guard storedVersion == version else {
                throw MarketDatabaseError.unsupportedSchemaVersion(storedVersion)
            }
        }
    }

    private static func currentVersion(in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: "PRAGMA user_version") ?? 0
    }

    private static func createCurrentSchema(in database: Database) throws {
        try database.create(table: "instruments") { table in
            table.column("id", .text).primaryKey()
            table.column("symbol", .text).notNull()
            table.column("name", .text).notNull()
            table.column("namespace", .text).notNull()
        }

        try database.create(table: "watchlist_items") { table in
            table.column("instrument_id", .text)
                .primaryKey()
                .references("instruments", onDelete: .cascade)
            table.column("sort_order", .integer).notNull().unique()
        }

        try database.create(table: "quote_sessions") { table in
            table.column("instrument_id", .text)
                .notNull()
                .references("instruments", onDelete: .cascade)
            table.column("session_date", .text).notNull()
            table.column("day_open", .double).notNull()
            table.column("previous_close", .double).notNull()
            table.column("last_price", .double).notNull()
            table.column("market_time", .datetime).notNull()
            table.column("received_at", .datetime).notNull()
            table.column("source", .text).notNull()
            table.primaryKey(["instrument_id", "session_date"])
        }

        try database.create(table: "minute_bars") { table in
            table.column("instrument_id", .text)
                .notNull()
                .references("instruments", onDelete: .cascade)
            table.column("session_date", .text).notNull()
            table.column("minute_at", .datetime).notNull()
            table.column("open", .double).notNull()
            table.column("close", .double).notNull()
            table.column("high", .double).notNull()
            table.column("low", .double).notNull()
            table.primaryKey(["instrument_id", "minute_at"])
        }
        try database.create(
            index: "minute_bars_by_instrument_and_session",
            on: "minute_bars",
            columns: ["instrument_id", "session_date"]
        )

        try database.create(table: "alert_configuration") { table in
            table.column("id", .integer).primaryKey()
            table.column("is_enabled", .boolean).notNull()
            table.column("basis", .text).notNull()
            table.column("rising_threshold", .double).notNull()
            table.column("falling_threshold", .double).notNull()
        }

        try database.create(table: "price_alert_targets") { table in
            table.column("instrument_id", .text)
                .primaryKey()
                .references("instruments", onDelete: .cascade)
            table.column("rising_price", .double).notNull()
            table.column("falling_price", .double).notNull()
        }

        try database.create(table: "application_metadata") { table in
            table.column("key", .text).primaryKey()
            table.column("value", .text).notNull()
        }
    }
}
