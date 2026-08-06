import Foundation

struct InstrumentID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(namespace: SymbolNamespace, symbol: String) {
        self.rawValue = "\(namespace.rawValue):\(namespace.normalize(symbol: symbol))"
    }

    var description: String { rawValue }
}

struct Instrument: Identifiable, Hashable, Sendable {
    let id: InstrumentID
    let symbol: String
    let name: String
    let namespace: SymbolNamespace

    var market: Market { namespace.market }

    init(symbol: String, name: String, namespace: SymbolNamespace) {
        let normalizedSymbol = namespace.normalize(symbol: symbol)
        self.id = InstrumentID(namespace: namespace, symbol: normalizedSymbol)
        self.symbol = normalizedSymbol
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.namespace = namespace
    }

    static let initialWatchlist: [Instrument] = [
        Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai),
        Instrument(symbol: "00700", name: "腾讯控股", namespace: .hongKong),
        Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates),
    ]
}

extension Instrument: Codable {
    private enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case namespace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            symbol: try container.decode(String.self, forKey: .symbol),
            name: try container.decode(String.self, forKey: .name),
            namespace: try container.decode(SymbolNamespace.self, forKey: .namespace)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(name, forKey: .name)
        try container.encode(namespace, forKey: .namespace)
    }
}
