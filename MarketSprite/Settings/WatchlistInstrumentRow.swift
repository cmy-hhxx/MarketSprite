import SwiftUI

struct WatchlistInstrumentRow: View {
    let instrument: Instrument
    let quote: QuoteSnapshot?
    let showsDivider: Bool
    let isMutating: Bool
    let removeAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary.opacity(isHovered ? 0.62 : 0.28))
                .frame(width: 32, height: SettingsVisualStyle.watchlistRowHeight)
                .help(tr("拖动排序"))
                .accessibilityHidden(true)

            WatchlistInstrumentIdentity(instrument: instrument)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let quote {
                    Text(changeText(for: quote))
                        .foregroundStyle(changeColor(for: quote))
                }
            }
            .font(
                .system(size: SettingsVisualStyle.changeFontSize, weight: .medium)
                    .monospacedDigit()
            )
            .frame(width: 96, alignment: .trailing)

            Button("移除 \(instrument.name)", systemImage: "trash", role: .destructive) {
                removeAction()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.secondary.opacity(isHovered ? 0.78 : 0.12))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .help(tr("删除"))
            .accessibilityHint(tr("会同时删除价格目标和行情缓存"))
            .disabled(isMutating)
        }
        .frame(height: SettingsVisualStyle.watchlistRowHeight)
        .contentShape(Rectangle())
        .background(
            isHovered ? SettingsVisualStyle.hoverBackground : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(alignment: .bottom) {
            if showsDivider {
                SettingsVisualStyle.separator
                    .frame(height: 1)
                    .padding(.leading, 32)
            }
        }
        .onHover { isHovered = $0 }
        .moveDisabled(isMutating)
    }

    private func changeText(for quote: QuoteSnapshot) -> String {
        String(
            format: "%@%.2f%%",
            quote.changePercent >= 0 ? "+" : "",
            quote.changePercent
        )
    }

    private func changeColor(for quote: QuoteSnapshot) -> Color {
        switch instrument.market.colorRole(isRising: quote.changePercent >= 0) {
        case .red:
            SettingsVisualStyle.marketRed
        case .green:
            SettingsVisualStyle.marketGreen
        }
    }
}
