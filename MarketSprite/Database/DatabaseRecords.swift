import Foundation

enum MarketDatabaseError: LocalizedError {
    case applicationSupportUnavailable
    case unrecognizedDatabase(Int)
    case integrityCheckFailed
    case invalidNamespace(String)
    case invalidInstrumentID(expected: InstrumentID, stored: String)
    case invalidWatchlist
    case quoteInstrumentMismatch(expected: InstrumentID, actual: InstrumentID)
    case invalidQuoteSource(String)
    case invalidAlertBasis(String)
    case invalidAlertConfiguration
    case unsupportedSchemaVersion(Int)
    case invalidQuote(String)
    case legacyDatabaseInvalid

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            tr("无法访问应用支持目录")
        case .unrecognizedDatabase:
            tr("数据库不属于 MarketSprite")
        case .integrityCheckFailed:
            tr("数据库完整性检查失败")
        case .invalidNamespace(let value):
            String(format: tr("数据库包含无效的标的代码域：%@"), value)
        case .invalidInstrumentID(let expected, let stored):
            String(
                format: tr("数据库标的 ID 不一致：应为 %@，实际为 %@"),
                expected.rawValue,
                stored
            )
        case .invalidWatchlist:
            tr("观察列表包含重复或无效的标的")
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
        case .invalidAlertConfiguration:
            tr("提醒设置无效")
        case .unsupportedSchemaVersion(let version):
            String(format: tr("不支持的数据库结构版本：%d"), version)
        case .invalidQuote(let message):
            String(format: tr("行情快照无效：%@"), message)
        case .legacyDatabaseInvalid:
            tr("旧版数据库无效，未执行数据切换")
        }
    }
}
