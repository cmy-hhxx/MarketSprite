struct IntradayExtremaSelection: Equatable, Sendable {
    let buyIndex: Int?
    let sellIndex: Int?

    init(closes: [Double]) {
        guard let firstClose = closes.first,
              closes.dropFirst().contains(where: { $0 != firstClose })
        else {
            buyIndex = nil
            sellIndex = nil
            return
        }

        var buyIndex = 0
        var sellIndex = 0
        for index in closes.indices {
            if closes[index] < closes[buyIndex] {
                buyIndex = index
            }
            if closes[index] > closes[sellIndex] {
                sellIndex = index
            }
        }

        let hasLaterHigherClose = closes.indices.contains { index in
            index > buyIndex && closes[index] > closes[buyIndex]
        }
        self.buyIndex = hasLaterHigherClose ? buyIndex : nil
        self.sellIndex = sellIndex
    }
}
