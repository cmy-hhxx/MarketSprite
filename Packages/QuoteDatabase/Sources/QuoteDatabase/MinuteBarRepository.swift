import Foundation
import GRDB

/// All SQLite access for minute bars lives here; app code must not import GRDB.
public final class MinuteBarRepository: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    public let databasePath: String

    init(dbQueue: DatabaseQueue, databasePath: String) {
        self.dbQueue = dbQueue
        self.databasePath = databasePath
    }

    /// Upsert bars for one symbol/day. Same `minute_at` overwrites OHLC and `fetched_at`.
    public func upsert(
        symbolID: String,
        tradeDate: String,
        previousClose: Double,
        bars: [MinuteBarInput],
        fetchedAt: Date
    ) throws {
        guard !bars.isEmpty else { return }
        try dbQueue.write { db in
            for bar in bars {
                try db.execute(
                    sql: """
                    INSERT INTO minute_bars (
                        symbol_id, trade_date, minute_at,
                        open, high, low, close, previous_close, fetched_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(symbol_id, minute_at) DO UPDATE SET
                        trade_date = excluded.trade_date,
                        open = excluded.open,
                        high = excluded.high,
                        low = excluded.low,
                        close = excluded.close,
                        previous_close = excluded.previous_close,
                        fetched_at = excluded.fetched_at
                    """,
                    arguments: [
                        symbolID,
                        tradeDate,
                        bar.minuteAt,
                        bar.open,
                        bar.high,
                        bar.low,
                        bar.close,
                        previousClose,
                        fetchedAt
                    ]
                )
            }
        }
    }

    public func clearAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM minute_bars")
        }
    }

    public func rowCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM minute_bars") ?? 0
        }
    }
}
