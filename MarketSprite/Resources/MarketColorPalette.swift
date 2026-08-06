import SwiftUI

enum MarketColorRole: Equatable, Sendable {
    case red
    case green
}

extension Market {
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

extension MarketColorRole {
    var color: Color {
        switch self {
        case .red:
            Color(red: 1.0, green: 0.30, blue: 0.38)
        case .green:
            Color(red: 0.18, green: 0.82, blue: 0.55)
        }
    }
}
