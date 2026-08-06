import Foundation

struct EastMoneySearchEnvelope: Decodable {
    let table: EastMoneySearchTable

    enum CodingKeys: String, CodingKey {
        case table = "QuotationCodeTable"
    }
}

struct EastMoneySearchTable: Decodable {
    let data: [EastMoneySearchItem]
    let status: Int

    enum CodingKeys: String, CodingKey {
        case data = "Data"
        case status = "Status"
    }
}

struct EastMoneySearchItem: Decodable {
    let code: String
    let name: String
    let classification: String
    let marketNumber: String
    let quoteIdentifier: String

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case name = "Name"
        case classification = "Classify"
        case marketNumber = "MktNum"
        case quoteIdentifier = "QuoteID"
    }
}

struct EastMoneyTrendEnvelope: Decodable {
    let returnCode: Int
    let data: EastMoneyTrendPayload?

    enum CodingKeys: String, CodingKey {
        case returnCode = "rc"
        case data
    }
}

struct EastMoneyTrendPayload: Decodable {
    let previousClose: Double
    let trends: [String]

    enum CodingKeys: String, CodingKey {
        case previousClose = "preClose"
        case trends
    }
}

struct TencentQuoteEnvelope: Decodable {
    let code: Int
    let data: [String: TencentQuotePayload]
}

struct TencentQuotePayload: Decodable {
    let minute: TencentMinuteDataPayload
    let quotes: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case minute = "data"
        case quotes = "qt"
    }
}

struct TencentMinuteDataPayload: Decodable {
    let values: [String]
    let date: String

    enum CodingKeys: String, CodingKey {
        case values = "data"
        case date
    }
}
