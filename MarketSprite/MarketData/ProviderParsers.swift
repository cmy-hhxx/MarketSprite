import Foundation

enum EastMoneyParser {
    private static let providerTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    static func minuteBar(from raw: String) -> MinuteBar? {
        let values = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count >= 5,
              let date = ProviderDateParser.minute(
                String(values[0]),
                timeZone: providerTimeZone
              ),
              let open = Double(values[1]),
              let close = Double(values[2]),
              let high = Double(values[3]),
              let low = Double(values[4]),
              close > 0
        else { return nil }

        return MinuteBar(
            time: date,
            open: open,
            close: close,
            high: high,
            low: low
        )
    }

    static func namespace(for item: EastMoneySearchItem) -> SymbolNamespace? {
        let classification = item.classification.lowercased()
        switch item.marketNumber {
        case "1":
            guard ["astock", "index", "fund"].contains(classification) else {
                return nil
            }
            return .shanghai
        case "0":
            guard ["astock", "index", "fund", "neeq"].contains(classification) else {
                return nil
            }
            if classification == "neeq"
                || item.code.hasPrefix("4")
                || item.code.hasPrefix("8")
                || item.code.hasPrefix("9") {
                return .beijing
            }
            return .shenzhen
        case "116":
            return classification == "hk" ? .hongKong : nil
        case "105", "106", "107":
            return classification == "usstock" ? .unitedStates : nil
        default:
            return nil
        }
    }

    static func quoteIdentifier(for instrument: Instrument) -> String {
        switch instrument.namespace {
        case .shanghai:
            "1.\(instrument.symbol)"
        case .shenzhen, .beijing:
            "0.\(instrument.symbol)"
        case .hongKong:
            "116.\(instrument.symbol)"
        case .unitedStates:
            "105.\(instrument.symbol)"
        }
    }

}

enum TencentParser {
    static func code(for instrument: Instrument) -> String {
        switch instrument.namespace {
        case .shanghai:
            return "sh\(instrument.symbol)"
        case .shenzhen:
            return "sz\(instrument.symbol)"
        case .beijing:
            return "bj\(instrument.symbol)"
        case .hongKong:
            return "hk\(instrument.symbol)"
        case .unitedStates:
            return "us\(instrument.symbol)"
        }
    }

    static func minuteBar(
        from raw: String,
        date: String,
        market: Market
    ) -> MinuteBar? {
        let values = raw.split(separator: " ", omittingEmptySubsequences: true)
        guard values.count >= 2,
              values[0].count == 4,
              let price = Double(values[1]),
              price > 0
        else { return nil }

        let day = date.isEmpty
            ? TradingCalendar.sessionDate(for: Date(), market: market)
            : date
        guard let parsedDate = ProviderDateParser.minute(
            "\(day) \(values[0])",
            timeZone: market.timeZone
        ) else { return nil }

        return MinuteBar(
            time: parsedDate,
            open: price,
            close: price,
            high: price,
            low: price
        )
    }

    static func hasDrawableData(_ bars: [MinuteBar]) -> Bool {
        bars.count >= 2
    }
}

private enum ProviderDateParser {
    static func minute(_ raw: String, timeZone: TimeZone) -> Date? {
        let digits = raw.utf8.filter { (48...57).contains($0) }
        guard digits.count >= 12 else { return nil }

        func value(at start: Int, length: Int) -> Int {
            digits[start..<(start + length)].reduce(0) { partial, digit in
                partial * 10 + Int(digit - 48)
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: value(at: 0, length: 4),
                month: value(at: 4, length: 2),
                day: value(at: 6, length: 2),
                hour: value(at: 8, length: 2),
                minute: value(at: 10, length: 2)
            )
        )
    }
}
