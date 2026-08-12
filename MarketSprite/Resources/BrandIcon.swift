import SwiftUI

enum BrandPalette {
    static let coral = Color(red: 1.0, green: 0.40, blue: 0.32)
    static let mint = Color(red: 0.39, green: 0.83, blue: 0.72)
    static let sky = Color(red: 0.38, green: 0.72, blue: 0.93)
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
