import SwiftUI

struct SettingsSectionIcon: View {
    let section: SettingsSection
    var size: CGFloat = SettingsVisualStyle.sidebarIconSize

    var body: some View {
        Image(systemName: section.icon)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                section.iconTint,
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
            .accessibilityHidden(true)
    }
}
