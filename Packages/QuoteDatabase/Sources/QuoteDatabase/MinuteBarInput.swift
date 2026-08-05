import Foundation

/// One intraday minute bar ready for persistence.
public struct MinuteBarInput: Sendable, Equatable {
    public var minuteAt: Date
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double

    public init(minuteAt: Date, open: Double, high: Double, low: Double, close: Double) {
        self.minuteAt = minuteAt
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}
