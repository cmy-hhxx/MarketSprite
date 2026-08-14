struct IntradayReviewMarkerSelection: Equatable, Sendable {
    let buyIndex: Int?
    let sellIndex: Int?

    init(buyIndex: Int?, sellIndex: Int?) {
        self.buyIndex = buyIndex
        self.sellIndex = sellIndex
    }
}
