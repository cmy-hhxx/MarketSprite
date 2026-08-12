import SwiftUI

struct InstrumentRowView: View {
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

    private var codeOpacity: Double {
        primaryOpacity * 0.72
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
                        showBSMarkers: instrument.market == .aShare
                            && TradingCalendar.shouldShowAShareExtrema(for: quote)
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
                            ? Color.white.opacity(primaryOpacity)
                            : changeRole.color.opacity(primaryOpacity)
                    )
                    .shadow(
                        color: Color.black.opacity(0.28 * primaryOpacity),
                        radius: 0.7,
                        y: 0.5
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isStale {
                    BrandIcon(
                        systemName: "clock.badge.exclamationmark",
                        size: 11,
                        showsBackground: false
                    )
                        .font(.system(size: 8))
                        .foregroundStyle(changeRole.color.opacity(primaryOpacity))
                }
            }

            HStack(spacing: 4) {
                Text(instrument.symbol)
                Text(instrument.namespace.displayName)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        changeRole.color.opacity(0.16 * primaryOpacity),
                        in: Capsule()
                    )
            }
            .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
            .tracking(0.12)
            .foregroundStyle(
                quote == nil
                    ? Color.white.opacity(codeOpacity)
                    : changeRole.color.opacity(codeOpacity)
            )
            .shadow(
                color: Color.black.opacity(0.22 * primaryOpacity),
                radius: 0.6,
                y: 0.5
            )
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(
            statusMessage
                ?? "\(instrument.namespace.displayName) · \(instrument.symbol)"
        )
    }

    @ViewBuilder
    private var price: some View {
        if let quote {
            VStack(alignment: .trailing, spacing: compact ? 1 : 3) {
                Text(priceText(quote.lastPrice))
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(changeRole.color.opacity(primaryOpacity))
                    .shadow(
                        color: Color.black.opacity(0.28 * primaryOpacity),
                        radius: 0.7,
                        y: 0.5
                    )

                Text(percentText(quote.changePercent))
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(changeRole.color.opacity(primaryOpacity))
                    .shadow(
                        color: Color.black.opacity(0.24 * primaryOpacity),
                        radius: 0.6,
                        y: 0.5
                    )
            }
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView()
                    .controlSize(.mini)
                    .opacity(isLoading ? 0.6 : 0)
                Text(tr(isLoading ? "拉取中" : "暂无数据"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(primaryOpacity))
            }
        }
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

struct IntradayChartView: View {
    let points: [MinuteBar]
    let market: Market
    let dayOpen: Double
    let previousClose: Double
    let colorRole: MarketColorRole
    let opacity: Double
    var showBSMarkers: Bool = false

    private let subdivisions = 8

    private var extremaExplanation: String {
        tr("收盘后复盘；S 为最高分钟收盘价，B 为随后出现上涨的最低分钟收盘价；不构成交易建议。")
    }

    var body: some View {
        let plottedPoints = points.compactMap { point -> (bar: MinuteBar, progress: Double)? in
            guard let progress = IntradayTimeline.progress(at: point.time, market: market)
            else { return nil }
            return (point, progress)
        }
        let closes = plottedPoints.map(\.bar.close)
        let extrema = showBSMarkers
            ? IntradayExtremaSelection(closes: closes)
            : nil

        Canvas { context, size in
            guard plottedPoints.count > 1 else { return }

            let minimum = min(closes.min() ?? dayOpen, dayOpen, previousClose)
            let maximum = max(closes.max() ?? dayOpen, dayOpen, previousClose)
            let padding = max((maximum - minimum) * 0.14, max(abs(previousClose) * 0.0008, 0.01))
            let low = minimum - padding
            let high = maximum + padding
            let range = max(high - low, 0.0001)
            let lastIndex = plottedPoints.count - 1

            func coordinate(progress: Double, price: Double) -> CGPoint {
                let x = size.width * CGFloat(min(max(progress, 0), 1))
                let normalized = (price - low) / range
                let y = size.height * (1 - CGFloat(normalized))
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
            waterline.move(to: CGPoint(x: 0, y: waterY))
            waterline.addLine(to: CGPoint(x: size.width, y: waterY))
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

                let steps = subdivisions
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let price = interpolatedClose(from: index - 1, to: index, t: t)
                    let previousProgress = plottedPoints[index - 1].progress
                    let currentProgress = plottedPoints[index].progress
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
                let point = coordinate(progress: last.progress, price: last.bar.close)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2.0, y: point.y - 2.0, width: 4.0, height: 4.0)),
                    with: .color(segmentRole.color.opacity(opacity))
                )
            }

            if let extrema {
                if let buyIndex = extrema.buyIndex {
                    drawBSMarker(
                        context: context,
                        canvasSize: size,
                        at: coordinate(
                            progress: plottedPoints[buyIndex].progress,
                            price: closes[buyIndex]
                        ),
                        label: "B",
                        color: MarketColorRole.green.color,
                        labelAbove: false
                    )
                }
                if let sellIndex = extrema.sellIndex {
                    drawBSMarker(
                        context: context,
                        canvasSize: size,
                        at: coordinate(
                            progress: plottedPoints[sellIndex].progress,
                            price: closes[sellIndex]
                        ),
                        label: "S",
                        color: MarketColorRole.red.color,
                        labelAbove: true
                    )
                }
            }
        }
        .accessibilityLabel(tr("当日分时曲线"))
        .accessibilityValue(showBSMarkers ? extremaExplanation : "")
        .help(showBSMarkers ? extremaExplanation : tr("当日分时曲线"))
    }

    private func drawBSMarker(
        context: GraphicsContext,
        canvasSize: CGSize,
        at point: CGPoint,
        label: String,
        color: Color,
        labelAbove: Bool
    ) {
        let outerDiameter: CGFloat = 9.5
        let whiteDiameter: CGFloat = 7.5
        let coreDiameter: CGFloat = 5
        let anchorInset = outerDiameter / 2 + 1
        let anchor = CGPoint(
            x: min(max(point.x, anchorInset), canvasSize.width - anchorInset),
            y: min(max(point.y, anchorInset), canvasSize.height - anchorInset)
        )

        let badgeSize = CGSize(width: 16, height: 14)
        let badgeX = min(
            max(anchor.x - badgeSize.width / 2, 2),
            canvasSize.width - badgeSize.width - 2
        )
        let preferredBadgeY = labelAbove
            ? anchor.y - badgeSize.height - 7
            : anchor.y + 7
        let badgeY = min(
            max(preferredBadgeY, 2),
            canvasSize.height - badgeSize.height - 2
        )
        let badge = CGRect(origin: CGPoint(x: badgeX, y: badgeY), size: badgeSize)

        if point != anchor {
            var attachment = Path()
            attachment.move(to: point)
            attachment.addLine(to: anchor)
            context.stroke(
                attachment,
                with: .color(Color.black.opacity(0.88)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            context.stroke(
                attachment,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
        }

        let guideStart = CGPoint(
            x: anchor.x,
            y: anchor.y + (labelAbove ? -outerDiameter / 2 : outerDiameter / 2)
        )
        let guideEnd = CGPoint(
            x: min(max(anchor.x, badge.minX + 3), badge.maxX - 3),
            y: labelAbove ? badge.maxY : badge.minY
        )
        var guide = Path()
        guide.move(to: guideStart)
        guide.addLine(to: guideEnd)
        context.stroke(
            guide,
            with: .color(Color.black.opacity(0.88)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        context.stroke(
            guide,
            with: .color(Color.white.opacity(0.96)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
        )

        context.fill(
            Path(ellipseIn: CGRect(
                x: anchor.x - outerDiameter / 2,
                y: anchor.y - outerDiameter / 2,
                width: outerDiameter,
                height: outerDiameter
            )),
            with: .color(Color.black.opacity(0.92))
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: anchor.x - whiteDiameter / 2,
                y: anchor.y - whiteDiameter / 2,
                width: whiteDiameter,
                height: whiteDiameter
            )),
            with: .color(Color.white)
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: anchor.x - coreDiameter / 2,
                y: anchor.y - coreDiameter / 2,
                width: coreDiameter,
                height: coreDiameter
            )),
            with: .color(color)
        )

        let badgePath = Path(roundedRect: badge, cornerRadius: 4)
        let shadowBadge = badge.offsetBy(dx: 0, dy: 1.2)
        context.fill(
            Path(roundedRect: shadowBadge, cornerRadius: 4),
            with: .color(Color.black.opacity(0.7))
        )
        context.fill(badgePath, with: .color(color))
        context.stroke(
            badgePath,
            with: .color(Color.white.opacity(0.92)),
            lineWidth: 1
        )

        let font = Font.system(size: 9.5, weight: .black, design: .rounded)
        let shadowText = Text(label)
            .font(font)
            .foregroundStyle(Color.black.opacity(0.78))
        let text = Text(label)
            .font(font)
            .foregroundStyle(Color.white)
        context.draw(
            shadowText,
            at: CGPoint(x: badge.midX, y: badge.midY + 0.7),
            anchor: .center
        )
        context.draw(text, at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
    }
}
