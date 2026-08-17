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
    let displayScale: Double

    private var changeRole: MarketColorRole {
        instrument.market.colorRole(isRising: (quote?.changePercent ?? 0) >= 0)
    }

    private var primaryOpacity: Double {
        min(max(labelOpacity, 0.72), 1)
    }

    private var layoutScale: CGFloat {
        CGFloat(min(max(displayScale, 0.65), 1.6))
    }

    private var labelWidth: CGFloat {
        scaled(compact ? 148 : 176, floor: compact ? 102 : 120)
    }

    private var chartWidth: CGFloat {
        scaled(compact ? 148 : 176, floor: compact ? 102 : 132)
    }

    private var priceWidth: CGFloat {
        scaled(compact ? 82 : 96, floor: compact ? 70 : 80)
    }

    private var rowSpacing: CGFloat { compact ? 6 : 8 }

    var body: some View {
        HStack(spacing: rowSpacing) {
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
        .padding(.horizontal, compact ? 2 : 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 0.5)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            HStack(spacing: 4) {
                Text(instrument.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(
                        .system(
                            size: scaled(
                                compact ? 10.5 : 12.5,
                                floor: compact ? 9 : 10
                            ),
                            weight: .semibold
                        )
                    )
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
            .font(
                .system(
                    size: scaled(
                        compact ? 8 : 9.5,
                        floor: compact ? 7.5 : 8
                    ),
                    weight: .medium
                )
            )
            .tracking(0.08)
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
                VStack(alignment: .trailing, spacing: compact ? 1 : 2) {
                    Text(priceText(quote.lastPrice))
                        .font(
                            .system(
                                size: scaled(
                                    compact ? 12.5 : 15.5,
                                    floor: compact ? 10 : 11
                                ),
                                weight: .semibold
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(changeRole.color)

                    Text(percentText(quote.changePercent))
                        .font(
                            .system(
                                size: scaled(
                                    compact ? 9 : 10.5,
                                    floor: compact ? 8 : 8.5
                                ),
                                weight: .medium
                            )
                        )
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

    private func scaled(_ value: CGFloat, floor: CGFloat) -> CGFloat {
        max(value * layoutScale, floor)
    }
}
