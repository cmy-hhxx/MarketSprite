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

    /// 名称/价格：保底不透明，避免发灰发糊。
    private var primaryOpacity: Double {
        max(0.92, min(labelOpacity, 1))
    }

    /// 代码行：略低于主文字，但仍保证可读。
    private var codeOpacity: Double {
        max(0.78, min(labelOpacity, 1))
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
                        dayOpen: quote.dayOpen,
                        previousClose: quote.previousClose,
                        colorRole: changeRole,
                        opacity: lineOpacity,
                        showBSMarkers: instrument.market == .aShare
                            && TradingCalendar.shouldShowAShareExtrema()
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
                    .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        quote == nil
                            ? Color.white.opacity(primaryOpacity)
                            : changeRole.color.opacity(primaryOpacity)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 8))
                        .foregroundStyle(changeRole.color.opacity(primaryOpacity))
                }
            }

            HStack(spacing: 4) {
                Text(instrument.symbol)
                Text(instrument.namespace.displayName)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(changeRole.color.opacity(0.22), in: Capsule())
            }
            .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(
                quote == nil
                    ? Color.white.opacity(codeOpacity)
                    : changeRole.color.opacity(codeOpacity)
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
                    .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(changeRole.color.opacity(primaryOpacity))

                Text(percentText(quote.changePercent))
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(changeRole.color.opacity(primaryOpacity))
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
    let dayOpen: Double
    let previousClose: Double
    let colorRole: MarketColorRole
    let opacity: Double
    var showBSMarkers: Bool = false

    private let subdivisions = 8
    private let buyMarkerColor = Color(red: 0.18, green: 0.82, blue: 0.55)
    private let sellMarkerColor = Color(red: 1.0, green: 0.30, blue: 0.38)

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }

            let closes = points.map(\.close)
            let minimum = min(closes.min() ?? dayOpen, dayOpen, previousClose)
            let maximum = max(closes.max() ?? dayOpen, dayOpen, previousClose)
            let padding = max((maximum - minimum) * 0.14, max(abs(previousClose) * 0.0008, 0.01))
            let low = minimum - padding
            let high = maximum + padding
            let range = max(high - low, 0.0001)
            let lastIndex = points.count - 1

            func coordinate(index: CGFloat, price: Double) -> CGPoint {
                let x = size.width * index / CGFloat(max(lastIndex, 1))
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

            let waterY = coordinate(index: 0, price: previousClose).y
            var waterline = Path()
            waterline.move(to: CGPoint(x: 0, y: waterY))
            waterline.addLine(to: CGPoint(x: size.width, y: waterY))
            context.stroke(
                waterline,
                with: .color(.white.opacity(0.22 * opacity)),
                style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
            )

            let strokeStyle = StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round)
            var segmentRole = colorRole
            for index in 1...lastIndex {
                let previous = closes[index - 1]
                let current = closes[index]
                let delta = current - previous
                if delta > 0 {
                    segmentRole = .red
                } else if delta < 0 {
                    segmentRole = .green
                }

                var segment = Path()
                let steps = subdivisions
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let price = interpolatedClose(from: index - 1, to: index, t: t)
                    let point = coordinate(index: CGFloat(index - 1) + t, price: price)
                    if step == 0 {
                        segment.move(to: point)
                    } else {
                        segment.addLine(to: point)
                    }
                }
                context.stroke(
                    segment,
                    with: .color(segmentRole.color.opacity(opacity)),
                    style: strokeStyle
                )
            }

            if let last = points.last {
                let point = coordinate(index: CGFloat(lastIndex), price: last.close)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2.0, y: point.y - 2.0, width: 4.0, height: 4.0)),
                    with: .color(segmentRole.color.opacity(opacity))
                )
            }

            if showBSMarkers {
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
                let markerOpacity = max(opacity, 0.92)
                drawBSMarker(
                    context: context,
                    canvasSize: size,
                    at: coordinate(index: CGFloat(buyIndex), price: closes[buyIndex]),
                    label: "B",
                    color: buyMarkerColor.opacity(markerOpacity),
                    labelAbove: false
                )
                drawBSMarker(
                    context: context,
                    canvasSize: size,
                    at: coordinate(index: CGFloat(sellIndex), price: closes[sellIndex]),
                    label: "S",
                    color: sellMarkerColor.opacity(markerOpacity),
                    labelAbove: true
                )
            }
        }
        .accessibilityLabel(tr("当日分时曲线"))
    }

    private func drawBSMarker(
        context: GraphicsContext,
        canvasSize: CGSize,
        at point: CGPoint,
        label: String,
        color: Color,
        labelAbove: Bool
    ) {
        let ring: CGFloat = 7.2
        let core: CGFloat = 4.6
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - ring / 2, y: point.y - ring / 2, width: ring, height: ring)),
            with: .color(Color.white.opacity(0.95))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - core / 2, y: point.y - core / 2, width: core, height: core)),
            with: .color(color)
        )

        let badgeY = labelAbove
            ? max(point.y - 13, 1)
            : min(point.y + 4, canvasSize.height - 12)
        let badgeX = min(max(point.x - 5.5, 1), canvasSize.width - 12)
        let badge = CGRect(x: badgeX, y: badgeY, width: 11, height: 11)
        context.fill(Path(roundedRect: badge, cornerRadius: 2.5), with: .color(color))
        let text = Text(label)
            .font(.system(size: 8.5, weight: .black, design: .rounded))
            .foregroundStyle(Color.white)
        context.draw(text, at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
    }
}
