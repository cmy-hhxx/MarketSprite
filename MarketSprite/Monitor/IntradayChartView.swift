import SwiftUI

struct ReviewMarkerInsets: Equatable {
    let horizontal: CGFloat
    let vertical: CGFloat

    static let zero = Self(horizontal: 0, vertical: 0)
}

struct ReviewMarkerLayout: Equatable {
    let markerPoint: CGPoint
    let labelPoint: CGPoint
    let fontSize: CGFloat
    let pointDiameter: CGFloat

    static func plotInsets(
        hasMarkers: Bool,
        isCompact: Bool
    ) -> ReviewMarkerInsets {
        guard hasMarkers else { return .zero }
        return ReviewMarkerInsets(
            horizontal: isCompact ? 5 : 6,
            vertical: isCompact ? 6 : 7
        )
    }

    init(
        canvasSize: CGSize,
        anchor: CGPoint,
        labelAbove: Bool,
        isCompact: Bool
    ) {
        fontSize = isCompact ? 9 : 10
        pointDiameter = 3

        let insets = Self.plotInsets(hasMarkers: true, isCompact: isCompact)
        let maximumAnchorX = max(canvasSize.width - insets.horizontal, insets.horizontal)
        let maximumAnchorY = max(canvasSize.height - insets.vertical, insets.vertical)
        markerPoint = CGPoint(
            x: min(max(anchor.x, insets.horizontal), maximumAnchorX),
            y: min(max(anchor.y, insets.vertical), maximumAnchorY)
        )

        let labelOffset: CGFloat = 7
        let labelBoundary = fontSize / 2 + 1
        let maximumLabelY = max(canvasSize.height - labelBoundary, labelBoundary)
        let preferredLabelY = markerPoint.y + (labelAbove ? -labelOffset : labelOffset)
        labelPoint = CGPoint(
            x: markerPoint.x,
            y: min(max(preferredLabelY, labelBoundary), maximumLabelY)
        )
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

    private func reviewMarkersExplanation(
        for reviewMarkers: IntradayReviewMarkerSelection?
    ) -> String {
        guard let reviewMarkers else {
            return tr("收盘复盘；本日未显示 B/S 标记；不构成交易建议。")
        }
        if reviewMarkers.buyIndex != nil {
            return tr("收盘复盘；B 与其后的 S 为最大正价差分钟收盘价；不构成交易建议。")
        }
        return tr("收盘复盘；S 为全日最高分钟收盘价；不构成交易建议。")
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
        let segmentRoles = IntradaySegmentColoring.roles(
            closes: closes,
            initialRole: colorRole
        )
        let reviewMarkers = preparation.reviewMarkers

        Canvas { context, size in
            guard plottedPoints.count > 1 else { return }

            let range = max(preparation.high - preparation.low, 0.0001)
            let isCompact = size.height < 52
            let markerInsets = ReviewMarkerLayout.plotInsets(
                hasMarkers: reviewMarkers != nil,
                isCompact: isCompact
            )
            let plotWidth = max(size.width - 2 * markerInsets.horizontal, 1)
            let plotHeight = max(size.height - 2 * markerInsets.vertical, 1)

            func coordinate(progress: Double, price: Double) -> CGPoint {
                let x = markerInsets.horizontal
                    + plotWidth * CGFloat(min(max(progress, 0), 1))
                let normalized = (price - preparation.low) / range
                let y = markerInsets.vertical + plotHeight * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            let waterY = coordinate(progress: 0, price: previousClose).y
            var waterline = Path()
            waterline.move(to: CGPoint(x: markerInsets.horizontal, y: waterY))
            waterline.addLine(to: CGPoint(x: size.width - markerInsets.horizontal, y: waterY))
            context.stroke(
                waterline,
                with: .color(.primary.opacity(0.08 + 0.05 * opacity)),
                style: StrokeStyle(lineWidth: 0.55, dash: [2, 4])
            )

            if let first = plottedPoints.first,
               let firstRole = segmentRoles.first {
                var segmentPath = Path()
                var activeRole = firstRole
                segmentPath.move(to: coordinate(progress: first.progress, price: first.close))

                for index in segmentRoles.indices {
                    let role = segmentRoles[index]
                    let start = plottedPoints[index]
                    if role != activeRole {
                        stroke(
                            segmentPath,
                            role: activeRole,
                            context: context,
                            lineWidth: isCompact ? 1.25 : 1.45
                        )
                        segmentPath = Path()
                        segmentPath.move(to: coordinate(progress: start.progress, price: start.close))
                        activeRole = role
                    }

                    let end = plottedPoints[index + 1]
                    segmentPath.addLine(to: coordinate(progress: end.progress, price: end.close))
                }

                stroke(
                    segmentPath,
                    role: activeRole,
                    context: context,
                    lineWidth: isCompact ? 1.25 : 1.45
                )
            }

            if let last = plottedPoints.last {
                let point = coordinate(progress: last.progress, price: last.close)
                let terminalRole = segmentRoles.last ?? colorRole
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                    with: .color(.white.opacity(0.92 * opacity))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 1.25, y: point.y - 1.25, width: 2.5, height: 2.5)),
                    with: .color(terminalRole.color.opacity(opacity))
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
                        isCompact: isCompact
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
                        isCompact: isCompact
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

    private func stroke(
        _ path: Path,
        role: MarketColorRole,
        context: GraphicsContext,
        lineWidth: CGFloat
    ) {
        guard !path.isEmpty else { return }
        context.stroke(
            path,
            with: .color(role.color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawReviewMarker(
        context: GraphicsContext,
        canvasSize: CGSize,
        at point: CGPoint,
        label: String,
        color: Color,
        labelAbove: Bool,
        isCompact: Bool
    ) {
        let layout = ReviewMarkerLayout(
            canvasSize: canvasSize,
            anchor: point,
            labelAbove: labelAbove,
            isCompact: isCompact
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: layout.markerPoint.x - layout.pointDiameter / 2,
                y: layout.markerPoint.y - layout.pointDiameter / 2,
                width: layout.pointDiameter,
                height: layout.pointDiameter
            )),
            with: .color(color.opacity(0.96 * opacity))
        )
        context.draw(
            Text(label)
                .font(.system(size: layout.fontSize, weight: .semibold))
                .foregroundStyle(color.opacity(0.92 * opacity)),
            at: layout.labelPoint,
            anchor: .center
        )
    }
}
