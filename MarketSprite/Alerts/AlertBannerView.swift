import SwiftUI

struct AlertBannerView: View {
    let alert: AlertEvent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false
    @State private var sparkle = false

    private var isBull: Bool {
        alert.direction == .rising
    }

    private var accentColor: Color {
        alert.instrument.market.colorRole(isRising: isBull).color
    }

    private var accentInkColor: Color {
        alert.instrument.market.colorRole(isRising: isBull).inkColor
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(isBull ? "BullMascot" : "BearMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .offset(y: isBobbing ? -4 : 2)
                .rotationEffect(.degrees(isBobbing ? -2 : 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(tr(isBull ? "小牛冲出来啦！" : "小熊来敲警钟"))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(BrandPalette.ink)
                Text(alertDetail)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(accentInkColor)
                Text(alert.triggeredAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(BrandPalette.ink.opacity(0.48))
            }

            BrandIcon(
                systemName: "sparkles",
                size: 12,
                showsBackground: false,
                tint: BrandPalette.coral.opacity(sparkle ? 1 : 0.45)
            )
        }
        .padding(.vertical, 9)
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandPalette.cream, Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.97)
                )
                .shadow(color: accentColor.opacity(0.2), radius: 18, y: 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accentColor.opacity(0.24), lineWidth: 0.8)
                }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                isBobbing = true
            }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                sparkle = true
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            guard isReduced else { return }
            isBobbing = false
            sparkle = false
        }
    }

    private var formattedPercent: String {
        String(
            format: "%@%.2f%%",
            alert.changePercent >= 0 ? "+" : "",
            alert.changePercent
        )
    }

    private var alertDetail: String {
        guard alert.basis == .targetPrice, let targetPrice = alert.targetPrice else {
            return "\(alert.instrument.name)  \(formattedPercent)"
        }
        return String(
            format: tr("%@  现价 %@%.2f · 目标 %@%.2f"),
            alert.instrument.name,
            alert.instrument.market.currencySymbol,
            alert.lastPrice,
            alert.instrument.market.currencySymbol,
            targetPrice
        )
    }
}
