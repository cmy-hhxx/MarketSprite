import SwiftUI

struct SettingsPageHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 12) {
            SettingsSectionIcon(section: section, size: 24)

            Text(section.title)
                .font(.system(size: SettingsVisualStyle.pageTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
