import Foundation

enum MarketDatabaseError: LocalizedError {
    case applicationSupportUnavailable
    case invalidNamespace(String)
    case invalidInstrumentID(expected: InstrumentID, stored: String)
    case quoteInstrumentMismatch(expected: InstrumentID, actual: InstrumentID)
    case invalidQuoteSource(String)
    case invalidAlertBasis(String)
    case unsupportedSchemaVersion(Int)
    case invalidQuote(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            tr("无法访问应用支持目录")
        case .invalidNamespace(let value):
            String(format: tr("数据库包含无效的标的代码域：%@"), value)
        case .invalidInstrumentID(let expected, let stored):
            String(
                format: tr("数据库标的 ID 不一致：应为 %@，实际为 %@"),
                expected.rawValue,
                stored
            )
        case .quoteInstrumentMismatch(let expected, let actual):
            String(
                format: tr("行情标的 ID 不一致：应为 %@，实际为 %@"),
                expected.rawValue,
                actual.rawValue
            )
        case .invalidQuoteSource(let value):
            String(format: tr("数据库包含无效的行情来源：%@"), value)
        case .invalidAlertBasis(let value):
            String(format: tr("数据库包含无效的提醒依据：%@"), value)
        case .unsupportedSchemaVersion(let version):
            String(format: tr("不支持的数据库结构版本：%d"), version)
        case .invalidQuote(let message):
            String(format: tr("行情快照无效：%@"), message)
        }
    }
}
