import Foundation

struct IntradayChartPoint: Equatable, Sendable {
    let progress: Double
    let close: Double
}

enum IntradaySegmentColoring {
    static func roles(
        closes: [Double],
        initialRole: MarketColorRole
    ) -> [MarketColorRole] {
        guard closes.count > 1 else { return [] }

        var currentRole = initialRole
        return zip(closes, closes.dropFirst()).map { previous, current in
            if current > previous {
                currentRole = .red
            } else if current < previous {
                currentRole = .green
            }
            return currentRole
        }
    }
}

struct IntradayChartPreparation: Equatable, Sendable {
    let points: [IntradayChartPoint]
    let low: Double
    let high: Double
    let reviewMarkers: IntradayReviewMarkerSelection?

    init(
        points sourcePoints: [MinuteBar],
        market: Market,
        dayOpen: Double,
        previousClose: Double,
        showReviewMarkers: Bool
    ) {
        let timeline = IntradayTimeline(market: market)
        var points: [IntradayChartPoint] = []
        points.reserveCapacity(sourcePoints.count)

        var minimum = min(dayOpen, previousClose)
        var maximum = max(dayOpen, previousClose)
        var lowestClose: Double?
        var highestClose: Double?
        var lowestIndex = 0
        var highestIndex = 0
        var bestProfit = 0.0
        var bestBuyIndex: Int?
        var bestSellIndex: Int?

        for point in sourcePoints {
            guard let progress = timeline.progress(at: point.time) else { continue }

            let index = points.count
            let close = point.close
            points.append(IntradayChartPoint(progress: progress, close: close))
            minimum = min(minimum, close)
            maximum = max(maximum, close)

            guard showReviewMarkers else { continue }

            guard let currentLowestClose = lowestClose else {
                lowestClose = close
                highestClose = close
                continue
            }

            let profit = close - currentLowestClose
            if profit > bestProfit {
                bestProfit = profit
                bestBuyIndex = lowestIndex
                bestSellIndex = index
            }
            if close < currentLowestClose {
                lowestClose = close
                lowestIndex = index
            }
            if let currentHighestClose = highestClose, close > currentHighestClose {
                highestClose = close
                highestIndex = index
            }
        }

        self.points = points
        let padding = max(
            (maximum - minimum) * 0.14,
            max(abs(previousClose) * 0.0008, 0.01)
        )
        low = minimum - padding
        high = maximum + padding
        guard showReviewMarkers,
              points.count > 1,
              let finalClose = points.last?.close,
              highestClose != nil
        else {
            reviewMarkers = nil
            return
        }

        if finalClose > previousClose,
           bestProfit > 0,
           let bestBuyIndex,
           let bestSellIndex {
            reviewMarkers = IntradayReviewMarkerSelection(
                buyIndex: bestBuyIndex,
                sellIndex: bestSellIndex
            )
        } else if finalClose != previousClose {
            reviewMarkers = IntradayReviewMarkerSelection(
                buyIndex: nil,
                sellIndex: highestIndex
            )
        } else {
            reviewMarkers = nil
        }
    }
}
