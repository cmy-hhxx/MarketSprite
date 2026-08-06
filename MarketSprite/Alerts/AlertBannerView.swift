import SwiftUI

struct AlertBannerView: View {
    let alert: AlertEvent
    @State private var isBobbing = false
    @State private var sparkle = false

    private var isBull: Bool {
        alert.direction == .rising
    }

    private var accentColor: Color {
        alert.instrument.market.colorRole(isRising: isBull).color
    }

    var body: some View {
        HStack(spacing: 10) {
            CartoonMascot(kind: isBull ? .bull : .bear)
                .frame(width: 66, height: 66)
                .offset(y: isBobbing ? -4 : 2)
                .rotationEffect(.degrees(isBobbing ? -2 : 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(tr(isBull ? "小牛冲出来啦！" : "小熊来敲警钟"))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(alertDetail)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                Text(alert.triggeredAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.yellow.opacity(sparkle ? 1 : 0.45))
        }
        .padding(.vertical, 9)
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.94))
                .shadow(color: accentColor.opacity(0.26), radius: 18, y: 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                isBobbing = true
            }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                sparkle = true
            }
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

private enum MascotKind {
    case bull
    case bear
}

private struct CartoonMascot: View {
    let kind: MascotKind

    var body: some View {
        ZStack {
            if kind == .bull {
                bull
            } else {
                bear
            }
        }
    }

    private var bull: some View {
        ZStack {
            horn
                .rotationEffect(.degrees(-32))
                .offset(x: -24, y: -22)
            horn
                .rotationEffect(.degrees(32))
                .offset(x: 24, y: -22)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.94, green: 0.58, blue: 0.28), Color(red: 0.70, green: 0.28, blue: 0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 55, height: 55)

            ears(color: Color(red: 0.74, green: 0.31, blue: 0.17))
            faceDetails(muzzleColor: Color(red: 0.98, green: 0.70, blue: 0.50))
        }
    }

    private var bear: some View {
        ZStack {
            HStack(spacing: 29) {
                Circle().fill(Color(red: 0.33, green: 0.47, blue: 0.35)).frame(width: 20, height: 20)
                Circle().fill(Color(red: 0.33, green: 0.47, blue: 0.35)).frame(width: 20, height: 20)
            }
            .offset(y: -20)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.47, green: 0.65, blue: 0.49), Color(red: 0.22, green: 0.38, blue: 0.27)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 56, height: 56)

            faceDetails(muzzleColor: Color(red: 0.76, green: 0.83, blue: 0.69))
        }
    }

    private var horn: some View {
        Capsule()
            .fill(Color(red: 1.0, green: 0.91, blue: 0.68))
            .frame(width: 10, height: 27)
    }

    private func ears(color: Color) -> some View {
        HStack(spacing: 37) {
            Circle().fill(color).frame(width: 14, height: 14)
            Circle().fill(color).frame(width: 14, height: 14)
        }
        .offset(y: -11)
    }

    private func faceDetails(muzzleColor: Color) -> some View {
        ZStack {
            HStack(spacing: 15) {
                Circle().fill(.black.opacity(0.82)).frame(width: 5, height: 7)
                Circle().fill(.black.opacity(0.82)).frame(width: 5, height: 7)
            }
            .offset(y: -6)

            Capsule()
                .fill(muzzleColor)
                .frame(width: 31, height: 20)
                .offset(y: 11)

            HStack(spacing: 8) {
                Circle().fill(.black.opacity(0.62)).frame(width: 3.5, height: 5)
                Circle().fill(.black.opacity(0.62)).frame(width: 3.5, height: 5)
            }
            .offset(y: 10)
        }
    }
}
