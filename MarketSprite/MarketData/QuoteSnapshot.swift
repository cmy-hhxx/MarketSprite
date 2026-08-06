import Foundation

enum QuoteSource: String, Codable, Sendable {
    case tencent
    case eastMoney
}

struct QuoteSnapshot: Equatable, Sendable {
    let instrumentID: InstrumentID
    let minuteBars: [MinuteBar]
    let dayOpen: Double
    let previousClose: Double
    let lastPrice: Double
    let marketTime: Date
    let receivedAt: Date
    let source: QuoteSource

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (lastPrice - previousClose) / previousClose * 100
    }
}
