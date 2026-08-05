import Foundation
import GRDB

/// Opens and migrates the local quotes SQLite database.
public enum QuoteDatabase {
    public static let defaultFileName = "quotes.sqlite"

    /// Opens `~/Library/Application Support/<appFolderName>/quotes.sqlite`.
    public static func openInApplicationSupport(
        appFolderName: String,
        fileName: String = defaultFileName
    ) throws -> MinuteBarRepository {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent(appFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName, isDirectory: false)
        return try open(at: url)
    }

    public static func open(at url: URL) throws -> MinuteBarRepository {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(dbQueue)
        return MinuteBarRepository(dbQueue: dbQueue, databasePath: url.path)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_minute_bars") { db in
            try db.create(table: "minute_bars") { table in
                table.column("symbol_id", .text).notNull()
                table.column("trade_date", .text).notNull()
                table.column("minute_at", .datetime).notNull()
                table.column("open", .double).notNull()
                table.column("high", .double).notNull()
                table.column("low", .double).notNull()
                table.column("close", .double).notNull()
                table.column("previous_close", .double).notNull()
                table.column("fetched_at", .datetime).notNull()
                table.primaryKey(["symbol_id", "minute_at"])
            }
            try db.create(
                index: "idx_minute_bars_symbol_trade_date",
                on: "minute_bars",
                columns: ["symbol_id", "trade_date"]
            )
        }
        return migrator
    }
}
