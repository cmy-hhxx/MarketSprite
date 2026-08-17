import SwiftUI

enum BrandPalette {
    static let coral = Color(red: 0.96, green: 0.40, blue: 0.36)
    static let mint = Color(red: 0.11, green: 0.68, blue: 0.55)
    static let coralInk = Color(red: 0.78, green: 0.29, blue: 0.27)
    static let mintInk = Color(red: 0.05, green: 0.48, blue: 0.41)
    static let sky = Color(red: 0.34, green: 0.58, blue: 0.64)
    static let cream = Color(red: 1.0, green: 0.95, blue: 0.85)
    static let ink = Color(red: 0.15, green: 0.17, blue: 0.22)
}

struct BrandIcon: View {
    let systemName: String
    var size: CGFloat = 13
    var showsBackground = true
    var tint: Color?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .symbolRenderingMode(.monochrome)
            .frame(width: size + 9, height: size + 9)
            .foregroundStyle(resolvedTint)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(resolvedTint.opacity(0.14))
                }
            }
            .accessibilityHidden(true)
    }

    private var resolvedTint: Color {
        if let tint { return tint }

        if systemName.contains("trash")
            || systemName.contains("exclamationmark")
            || systemName.contains("bad") {
            return BrandPalette.coral
        }
        if systemName.contains("bell")
            || systemName.contains("speaker")
            || systemName.contains("sparkles")
            || systemName == "scope" {
            return BrandPalette.coral
        }
        if systemName.contains("paintbrush")
            || systemName.contains("rectangle")
            || systemName.contains("square.on.square")
            || systemName.contains("textformat") {
            return BrandPalette.sky
        }
        return BrandPalette.mint
    }
}
