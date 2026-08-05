import Foundation

enum StockMarket: String, Codable, CaseIterable, Sendable {
    case aShare
    case hongKong
    case unitedStates

    var displayName: String {
        switch self {
        case .aShare: tr("A股")
        case .hongKong: tr("港股")
        case .unitedStates: tr("美股")
        }
    }

    var currencySymbol: String {
        switch self {
        case .aShare: "¥"
        case .hongKong: "HK$"
        case .unitedStates: "$"
        }
    }

    /// 中国内地和香港采用红涨绿跌，美股采用绿涨红跌。
    func colorRole(isRising: Bool) -> MarketColorRole {
        switch self {
        case .aShare, .hongKong:
            isRising ? .red : .green
        case .unitedStates:
            isRising ? .green : .red
        }
    }
}

enum MarketColorRole: String, Equatable, Sendable {
    case red
    case green
}

struct StockSymbol: Identifiable, Hashable, Sendable {
    var id: String { quoteID }

    let code: String
    let name: String
    let market: StockMarket
    let quoteID: String

    init(code: String, name: String, market: StockMarket, quoteID: String) {
        self.code = code
        self.name = name
        self.market = market
        self.quoteID = quoteID
    }

    /// Eastmoney secid when quoteID is omitted from JSON.
    static func defaultQuoteID(code: String, market: StockMarket) -> String {
        switch market {
        case .aShare:
            code.hasPrefix("6") ? "1.\(code)" : "0.\(code)"
        case .hongKong:
            "116.\(code)"
        case .unitedStates:
            "105.\(code.uppercased())"
        }
    }

    static let initialSymbols: [StockSymbol] = [
        StockSymbol(
            code: "600519",
            name: "贵州茅台",
            market: .aShare,
            quoteID: "1.600519"
        ),
        StockSymbol(
            code: "00700",
            name: "腾讯控股",
            market: .hongKong,
            quoteID: "116.00700"
        ),
        StockSymbol(
            code: "AAPL",
            name: "苹果",
            market: .unitedStates,
            quoteID: "105.AAPL"
        )
    ]
}

extension StockSymbol: Codable {
    enum CodingKeys: String, CodingKey {
        case code, name, market, quoteID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let name = try container.decode(String.self, forKey: .name)
        let market = try container.decode(StockMarket.self, forKey: .market)
        let rawQuoteID = try container.decodeIfPresent(String.self, forKey: .quoteID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteID = (rawQuoteID?.isEmpty == false)
            ? rawQuoteID!
            : Self.defaultQuoteID(code: code, market: market)
        self.init(code: code, name: name, market: market, quoteID: quoteID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encode(market, forKey: .market)
        try container.encode(quoteID, forKey: .quoteID)
    }
}

enum ImportSymbolsResult: Equatable, Sendable {
    case success(count: Int)
    case failure(String)

    var message: String {
        switch self {
        case .success(let count):
            String(format: tr("已导入 %d 只股票"), count)
        case .failure(let message):
            message
        }
    }
}

struct IntradayPoint: Identifiable, Hashable, Sendable {
    var id: Date { time }

    let time: Date
    let open: Double
    let close: Double
    let high: Double
    let low: Double
}

struct StockQuote: Identifiable, Sendable {
    var id: String { symbol.id }

    let symbol: StockSymbol
    let points: [IntradayPoint]
    let dayOpen: Double
    let previousClose: Double
    let lastPrice: Double
    let updatedAt: Date
    var isStale: Bool
    var statusMessage: String?

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (lastPrice - previousClose) / previousClose * 100
    }
}

enum ThresholdDirection: String, Sendable {
    case rising
    case falling
}

enum AlertBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage
    case targetPrice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .percentage: tr("昨收涨跌幅")
        case .targetPrice: tr("目标价格")
        }
    }
}

struct PriceAlertTargets: Codable, Equatable, Sendable {
    var risingPrice: Double
    var fallingPrice: Double

    var isEnabled: Bool {
        risingPrice > 0 || fallingPrice > 0
    }
}

struct ThresholdAlert: Identifiable, Sendable {
    let id = UUID()
    let symbol: StockSymbol
    let percent: Double
    let lastPrice: Double
    let targetPrice: Double?
    let basis: AlertBasis
    let direction: ThresholdDirection
    let triggeredAt: Date
}

enum AlertArmState: String {
    case armed
    case risingTriggered
    case fallingTriggered
}

enum ShortcutModifierOption: String, Codable, CaseIterable, Identifiable {
    case commandOption
    case commandShift
    case controlOption
    case controlShift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandOption: "⌘⌥"
        case .commandShift: "⌘⇧"
        case .controlOption: "⌃⌥"
        case .controlShift: "⌃⇧"
        }
    }
}

enum ShortcutKeyOption: String, Codable, CaseIterable, Identifiable {
    case s = "S"
    case p = "P"
    case h = "H"
    case k = "K"
    case d = "D"
    case f = "F"
    case space = "Space"

    var id: String { rawValue }
    var displayName: String { self == .space ? tr("空格") : rawValue }
}

extension Notification.Name {
    static let marketSpriteShortcutChanged = Notification.Name("marketSprite.shortcutChanged")
}

struct ThresholdGate {
    private(set) var state: AlertArmState = .armed

    mutating func evaluate(
        percent: Double,
        risingThreshold: Double,
        fallingThreshold: Double,
        hysteresis: Double = 0.15
    ) -> ThresholdDirection? {
        if percent >= risingThreshold, state != .risingTriggered {
            state = .risingTriggered
            return .rising
        }
        if percent <= -fallingThreshold, state != .fallingTriggered {
            state = .fallingTriggered
            return .falling
        }
        if percent < risingThreshold - hysteresis,
           percent > -fallingThreshold + hysteresis {
            state = .armed
        }
        return nil
    }

    mutating func evaluatePrice(
        price: Double,
        risingTarget: Double,
        fallingTarget: Double,
        hysteresisRatio: Double = 0.0015
    ) -> ThresholdDirection? {
        if risingTarget > 0, price >= risingTarget, state != .risingTriggered {
            state = .risingTriggered
            return .rising
        }
        if fallingTarget > 0, price <= fallingTarget, state != .fallingTriggered {
            state = .fallingTriggered
            return .falling
        }

        let isBelowRisingRearm = risingTarget <= 0
            || price < risingTarget * (1 - hysteresisRatio)
        let isAboveFallingRearm = fallingTarget <= 0
            || price > fallingTarget * (1 + hysteresisRatio)
        if isBelowRisingRearm, isAboveFallingRearm {
            state = .armed
        }
        return nil
    }
}

enum QuoteServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedSymbol
    case noIntradayData
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            tr("行情地址无效")
        case .invalidResponse:
            tr("行情返回格式异常")
        case .unsupportedSymbol:
            tr("暂不支持这个股票或市场")
        case .noIntradayData:
            tr("今天暂无分时数据")
        case .server(let message):
            message
        }
    }
}
