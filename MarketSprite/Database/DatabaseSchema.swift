import GRDB

enum DatabaseSchema {
    static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_watchlist") { database in
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
        }
        migrator.registerMigration("v2_quotes") { database in
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
        }
        migrator.registerMigration("v3_alerts") { database in
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
        }
        migrator.registerMigration("v4_metadata") { database in
            try database.create(table: "application_metadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
        }
        try migrator.migrate(writer)
    }
}
