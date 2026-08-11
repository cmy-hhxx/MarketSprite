import Foundation

actor PublicMarketDataClient: MarketDataClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let searchToken = "D43BF722C8E33DA55D5C6812C6C46"
    private var eastMoneyIdentifiers: [InstrumentID: String] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "searchapi.eastmoney.com"
        components.path = "/api/suggest/get"
        components.queryItems = [
            URLQueryItem(name: "input", value: cleanQuery),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "token", value: searchToken),
            URLQueryItem(name: "count", value: "20"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(EastMoneySearchEnvelope.self, from: data)
        guard response.table.status == 0 else {
            throw MarketDataError.provider(tr("搜索服务暂不可用"))
        }

        var seen = Set<InstrumentID>()
        var instruments: [Instrument] = []
        for item in response.table.data {
            guard let namespace = EastMoneyParser.namespace(for: item) else { continue }
            guard let instrument = try? Instrument(
                validatingSymbol: item.code,
                name: item.name,
                namespace: namespace
            ) else { continue }
            guard seen.insert(instrument.id).inserted else { continue }
            if instrument.namespace == .unitedStates,
               !item.quoteIdentifier.isEmpty {
                eastMoneyIdentifiers[instrument.id] = item.quoteIdentifier
            }
            instruments.append(instrument)
        }
        return instruments
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        do {
            return try await fetchTencentQuote(for: instrument)
        } catch {
            try Task.checkCancellation()
            return try await fetchEastMoneyQuote(for: instrument)
        }
    }

    private func fetchTencentQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        let providerCode = TencentParser.code(for: instrument)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "web.ifzq.gtimg.cn"
        components.path = "/appstock/app/minute/query"
        components.queryItems = [URLQueryItem(name: "code", value: providerCode)]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(TencentQuoteEnvelope.self, from: data)
        guard response.code == 0,
              let payload = response.data[providerCode],
              let fields = payload.quotes[providerCode],
              fields.count > 5
        else { throw MarketDataError.invalidResponse }

        let date = payload.minute.date.isEmpty
            ? Self.datePrefix(from: fields[safe: 30] ?? "")
            : payload.minute.date
        let bars = payload.minute.values.compactMap {
            TencentParser.minuteBar(from: $0, date: date, market: instrument.market)
        }
        guard TencentParser.hasDrawableData(bars), let last = bars.last else {
            throw MarketDataError.noIntradayData
        }

        let dayOpen = Double(fields[5]).flatMap { $0 > 0 ? $0 : nil }
            ?? bars.first?.close
            ?? last.close
        let previousClose = Double(fields[4]).flatMap { $0 > 0 ? $0 : nil }
            ?? dayOpen
        let latestPrice = Double(fields[3]).flatMap { $0 > 0 ? $0 : nil }
            ?? last.close

        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: dayOpen,
            previousClose: previousClose,
            lastPrice: latestPrice,
            marketTime: last.time,
            receivedAt: Date(),
            source: .tencent
        )
    }

    private func fetchEastMoneyQuote(
        for instrument: Instrument
    ) async throws -> QuoteSnapshot {
        let quoteIdentifier = try await eastMoneyQuoteIdentifier(for: instrument)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2delay.eastmoney.com"
        components.path = "/api/qt/stock/trends2/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: quoteIdentifier),
            URLQueryItem(
                name: "fields1",
                value: "f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13"
            ),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58"),
            URLQueryItem(name: "iscr", value: "0"),
            URLQueryItem(name: "ndays", value: "1"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(EastMoneyTrendEnvelope.self, from: data)
        guard response.returnCode == 0, let payload = response.data else {
            throw MarketDataError.provider(tr("行情服务暂不可用"))
        }

        let bars = payload.trends.compactMap {
            EastMoneyParser.minuteBar(from: $0)
        }
        guard TencentParser.hasDrawableData(bars),
              let first = bars.first,
              let last = bars.last
        else { throw MarketDataError.noIntradayData }

        let dayOpen = first.open > 0 ? first.open : first.close
        let previousClose = payload.previousClose > 0
            ? payload.previousClose
            : dayOpen
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: dayOpen,
            previousClose: previousClose,
            lastPrice: last.close,
            marketTime: last.time,
            receivedAt: Date(),
            source: .eastMoney
        )
    }

    private func eastMoneyQuoteIdentifier(for instrument: Instrument) async throws -> String {
        guard instrument.namespace == .unitedStates else {
            return EastMoneyParser.quoteIdentifier(for: instrument)
        }
        if let cached = eastMoneyIdentifiers[instrument.id] {
            return cached
        }

        do {
            _ = try await searchInstruments(matching: instrument.symbol)
        } catch {
            try Task.checkCancellation()
        }
        return eastMoneyIdentifiers[instrument.id]
            ?? EastMoneyParser.quoteIdentifier(for: instrument)
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw MarketDataError.invalidResponse }
        return data
    }

    private static func datePrefix(from raw: String) -> String {
        raw.count >= 10 ? String(raw.prefix(10)) : ""
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
