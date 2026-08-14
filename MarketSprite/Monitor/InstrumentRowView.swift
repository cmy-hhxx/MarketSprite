import SwiftUI

struct InstrumentRowView: View, Equatable {
    let instrument: Instrument
    let quote: QuoteSnapshot?
    let isLoading: Bool
    let isStale: Bool
    let statusMessage: String?
    let lineOpacity: Double
    let labelOpacity: Double
    let compact: Bool

    private var changeRole: MarketColorRole {
        instrument.market.colorRole(isRising: (quote?.changePercent ?? 0) >= 0)
    }

    private var primaryOpacity: Double {
        min(max(labelOpacity, 0), 1)
    }

    private var labelWidth: CGFloat { compact ? 148 : 176 }
    private var chartWidth: CGFloat { compact ? 148 : 176 }
    private var priceWidth: CGFloat { compact ? 82 : 96 }

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            label
                .frame(width: labelWidth, alignment: .leading)

            Group {
                if let quote, quote.minuteBars.count > 1 {
                    IntradayChartView(
                        points: quote.minuteBars,
                        market: instrument.market,
                        dayOpen: quote.dayOpen,
                        previousClose: quote.previousClose,
                        colorRole: changeRole,
                        opacity: lineOpacity,
                        showReviewMarkers: instrument.market == .aShare
                            && TradingCalendar.shouldShowAShareReviewMarkers(for: quote)
                    )
                } else {
                    placeholder
                }
            }
            .frame(width: chartWidth, alignment: .leading)

            Spacer(minLength: 0)

            price
                .frame(width: priceWidth, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 0.5)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            HStack(spacing: 4) {
                Text(instrument.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
                    .foregroundStyle(
                        quote == nil
                            ? Color.white
                            : changeRole.color
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isStale {
                    BrandIcon(
                        systemName: "clock.badge.exclamationmark",
                        size: 11,
                        showsBackground: false
                    )
                        .font(.system(size: 8))
                        .foregroundStyle(changeRole.color)
                }
            }

            HStack(spacing: 4) {
                Text(instrument.symbol)
                Text(instrument.namespace.displayName)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        changeRole.color.opacity(0.16),
                        in: Capsule()
                    )
            }
            .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
            .tracking(0.12)
            .foregroundStyle(
                quote == nil
                    ? Color.white.opacity(0.72)
                    : changeRole.color.opacity(0.72)
            )
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(primaryOpacity)
        .help(
            statusMessage
                ?? "\(instrument.namespace.displayName) · \(instrument.symbol)"
        )
    }

    private var price: some View {
        Group {
            if let quote {
                VStack(alignment: .trailing, spacing: compact ? 1 : 3) {
                    Text(priceText(quote.lastPrice))
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(changeRole.color)

                    Text(percentText(quote.changePercent))
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(changeRole.color.opacity(0.72))
                }
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView()
                        .controlSize(.mini)
                        .opacity(isLoading ? 0.6 : 0)
                    Text(tr(isLoading ? "拉取中" : "暂无数据"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .opacity(primaryOpacity)
    }

    private var placeholder: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.04))
                .frame(height: 2)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.55)
            }
        }
    }

    private func priceText(_ value: Double) -> String {
        if value >= 1_000 {
            return String(format: "%.2f", value)
        }
        if value >= 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%@%.2f%%", value >= 0 ? "+" : "", value)
    }
}

struct IntradayChartView: View, Equatable {
    let points: [MinuteBar]
    let market: Market
    let dayOpen: Double
    let previousClose: Double
    let colorRole: MarketColorRole
    let opacity: Double
    var showReviewMarkers = false

    private let subdivisions = 8

    private func reviewMarkersExplanation(
        for reviewMarkers: IntradayReviewMarkerSelection?
    ) -> String {
        guard let reviewMarkers else {
            return tr("收盘后复盘；本日未显示 B/S 标记；不构成交易建议。")
        }
        if reviewMarkers.buyIndex != nil {
            return tr("收盘后复盘；B 与其后的 S 为最大正价差分钟收盘价；不构成交易建议。")
        }
        return tr("收盘后复盘；S 为全日最高分钟收盘价；不构成交易建议。")
    }

    var body: some View {
        let preparation = IntradayChartPreparation(
            points: points,
            market: market,
            dayOpen: dayOpen,
            previousClose: previousClose,
            showReviewMarkers: showReviewMarkers
        )
        let plottedPoints = preparation.points
        let closes = plottedPoints.map(\.close)
        let reviewMarkers = preparation.reviewMarkers

        Canvas { context, size in
            guard plottedPoints.count > 1 else { return }

            let range = max(preparation.high - preparation.low, 0.0001)
            let lastIndex = plottedPoints.count - 1
            let isCompact = size.height < 52
            let horizontalMarkerInset: CGFloat = reviewMarkers == nil
                ? 0
                : (isCompact ? 7.5 : 8.5)
            let verticalMarkerInset: CGFloat = reviewMarkers == nil
                ? 0
                : (isCompact ? 12 : 16)
            let plotWidth = max(size.width - 2 * horizontalMarkerInset, 1)
            let plotHeight = max(size.height - 2 * verticalMarkerInset, 1)

            func coordinate(progress: Double, price: Double) -> CGPoint {
                let x = horizontalMarkerInset
                    + plotWidth * CGFloat(min(max(progress, 0), 1))
                let normalized = (price - preparation.low) / range
                let y = verticalMarkerInset + plotHeight * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            func close(at index: Int) -> Double {
                closes[min(max(index, 0), lastIndex)]
            }

            /// Catmull-Rom：在原始分钟点之间插值，曲线更顺，不丢着色语义。
            func interpolatedClose(from i1: Int, to i2: Int, t: CGFloat) -> Double {
                let p0 = close(at: i1 - 1)
                let p1 = close(at: i1)
                let p2 = close(at: i2)
                let p3 = close(at: i2 + 1)
                let t2 = t * t
                let t3 = t2 * t
                return 0.5 * (
                    (2 * p1)
                    + (-p0 + p2) * Double(t)
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * Double(t2)
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * Double(t3)
                )
            }

            let waterY = coordinate(progress: 0, price: previousClose).y
            var waterline = Path()
            waterline.move(to: CGPoint(x: horizontalMarkerInset, y: waterY))
            waterline.addLine(to: CGPoint(x: size.width - horizontalMarkerInset, y: waterY))
            context.stroke(
                waterline,
                with: .color(.black.opacity(0.2 + 0.14 * opacity)),
                style: StrokeStyle(lineWidth: 1.8, dash: [3, 4])
            )
            context.stroke(
                waterline,
                with: .color(.white.opacity(0.3 + 0.22 * opacity)),
                style: StrokeStyle(lineWidth: 0.7, dash: [3, 4])
            )

            let strokeStyle = StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round)
            var segmentRole = colorRole
            var risingPath = Path()
            var fallingPath = Path()
            for index in 1...lastIndex {
                let previous = closes[index - 1]
                let current = closes[index]
                let delta = current - previous
                if delta > 0 {
                    segmentRole = .red
                } else if delta < 0 {
                    segmentRole = .green
                }

                let previousProgress = plottedPoints[index - 1].progress
                let currentProgress = plottedPoints[index].progress
                let horizontalDistance = abs(currentProgress - previousProgress) * Double(size.width)
                let steps = min(max(Int(horizontalDistance.rounded(.up)), 1), subdivisions)
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let price = interpolatedClose(from: index - 1, to: index, t: t)
                    let progress = previousProgress
                        + (currentProgress - previousProgress) * Double(t)
                    let point = coordinate(progress: progress, price: price)
                    if segmentRole == .red {
                        if step == 0 {
                            risingPath.move(to: point)
                        } else {
                            risingPath.addLine(to: point)
                        }
                    } else {
                        if step == 0 {
                            fallingPath.move(to: point)
                        } else {
                            fallingPath.addLine(to: point)
                        }
                    }
                }
            }
            if !risingPath.isEmpty {
                context.stroke(
                    risingPath,
                    with: .color(MarketColorRole.red.color.opacity(opacity)),
                    style: strokeStyle
                )
            }
            if !fallingPath.isEmpty {
                context.stroke(
                    fallingPath,
                    with: .color(MarketColorRole.green.color.opacity(opacity)),
                    style: strokeStyle
                )
            }

            if let last = plottedPoints.last {
                let point = coordinate(progress: last.progress, price: last.close)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2.0, y: point.y - 2.0, width: 4.0, height: 4.0)),
                    with: .color(segmentRole.color.opacity(opacity))
                )
            }

            if let reviewMarkers {
                if let buyIndex = reviewMarkers.buyIndex {
                    drawReviewMarker(
                        context: context,
                        canvasSize: size,
                        at: coordinate(
                            progress: plottedPoints[buyIndex].progress,
                            price: closes[buyIndex]
                        ),
                        label: "B",
                        color: MarketColorRole.green.color,
                        labelAbove: false,
                        opacity: opacity
                    )
                }
                if let sellIndex = reviewMarkers.sellIndex {
                    drawReviewMarker(
                        context: context,
                        canvasSize: size,
                        at: coordinate(
                            progress: plottedPoints[sellIndex].progress,
                            price: closes[sellIndex]
                        ),
                        label: "S",
                        color: MarketColorRole.red.color,
                        labelAbove: true,
                        opacity: opacity
                    )
                }
            }
        }
        .accessibilityLabel(tr("当日分时曲线"))
        .accessibilityValue(
            showReviewMarkers ? reviewMarkersExplanation(for: reviewMarkers) : ""
        )
        .help(
            showReviewMarkers
                ? reviewMarkersExplanation(for: reviewMarkers)
                : tr("当日分时曲线")
        )
    }

    private func drawReviewMarker(
        context: GraphicsContext,
        canvasSize: CGSize,
        at point: CGPoint,
        label: String,
        color: Color,
        labelAbove: Bool,
        opacity: Double
    ) {
        let isCompact = canvasSize.height < 52
        let fontSize: CGFloat = isCompact ? 12 : 14
        let pointDiameter: CGFloat = 4
        let horizontalInset = fontSize * 0.45 + 2
        let anchor = CGPoint(
            x: min(max(point.x, horizontalInset), canvasSize.width - horizontalInset),
            y: point.y
        )
        let labelOffset = fontSize * 0.8
        let preferredLabelY = anchor.y + (labelAbove ? -labelOffset : labelOffset)
        let labelY = min(
            max(preferredLabelY, fontSize * 0.5 + 1),
            canvasSize.height - fontSize * 0.5 - 1
        )

        var guide = Path()
        guide.move(to: anchor)
        guide.addLine(to: CGPoint(x: anchor.x, y: labelY))
        context.stroke(
            guide,
            with: .color(Color.primary.opacity(0.34 * opacity)),
            style: StrokeStyle(lineWidth: 0.75, dash: [1.25, 2.25])
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: anchor.x - pointDiameter / 2,
                y: anchor.y - pointDiameter / 2,
                width: pointDiameter,
                height: pointDiameter
            )),
            with: .color(color.opacity(opacity))
        )
        context.draw(
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.66 * opacity)),
            at: CGPoint(x: anchor.x, y: labelY),
            anchor: .center
        )
    }
}
