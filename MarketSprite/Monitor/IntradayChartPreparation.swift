import Foundation

struct IntradayChartPoint: Equatable, Sendable {
    let progress: Double
    let close: Double
}

struct IntradayChartPreparation: Equatable, Sendable {
    let points: [IntradayChartPoint]
    let low: Double
    let high: Double
    let extrema: IntradayExtremaSelection?

    init(
        points sourcePoints: [MinuteBar],
        market: Market,
        dayOpen: Double,
        previousClose: Double,
        showBSMarkers: Bool
    ) {
        let timeline = IntradayTimeline(market: market)
        var points: [IntradayChartPoint] = []
        points.reserveCapacity(sourcePoints.count)

        var minimum = min(dayOpen, previousClose)
        var maximum = max(dayOpen, previousClose)
        var firstClose: Double?
        var lowestClose = 0.0
        var highestClose = 0.0
        var buyIndex = 0
        var sellIndex = 0
        var hasVariation = false
        var hasLaterHigherClose = false

        for point in sourcePoints {
            guard let progress = timeline.progress(at: point.time) else { continue }

            let index = points.count
            let close = point.close
            points.append(IntradayChartPoint(progress: progress, close: close))
            minimum = min(minimum, close)
            maximum = max(maximum, close)

            if let firstClose {
                hasVariation = hasVariation || close != firstClose
            } else {
                firstClose = close
                lowestClose = close
                highestClose = close
                continue
            }

            if close < lowestClose {
                lowestClose = close
                buyIndex = index
                hasLaterHigherClose = false
            } else if close > lowestClose {
                hasLaterHigherClose = true
            }
            if close > highestClose {
                highestClose = close
                sellIndex = index
            }
        }

        self.points = points
        let padding = max(
            (maximum - minimum) * 0.14,
            max(abs(previousClose) * 0.0008, 0.01)
        )
        low = minimum - padding
        high = maximum + padding
        if showBSMarkers, hasVariation {
            extrema = IntradayExtremaSelection(
                buyIndex: hasLaterHigherClose ? buyIndex : nil,
                sellIndex: sellIndex
            )
        } else {
            extrema = nil
        }
    }
}
