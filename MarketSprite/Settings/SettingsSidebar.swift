import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection
    @State private var hoveredSection: SettingsSection?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        SettingsSectionIcon(section: section)

                        Text(section.title)
                            .font(
                                .system(
                                    size: SettingsVisualStyle.sidebarFontSize,
                                    weight: selectedSection == section ? .medium : .regular
                                )
                            )
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        selectedSection == section
                            ? Color.primary
                            : Color.primary.opacity(0.72)
                    )
                    .padding(.horizontal, SettingsVisualStyle.sidebarRowHorizontalPadding)
                    .frame(maxWidth: .infinity, minHeight: SettingsVisualStyle.sidebarRowHeight)
                    .contentShape(Rectangle())
                    .background(
                        rowBackground(for: section),
                        in: RoundedRectangle(
                            cornerRadius: SettingsVisualStyle.sidebarRowCornerRadius
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .onHover { isHovered in
                    hoveredSection = isHovered ? section : nil
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsVisualStyle.sidebarHorizontalPadding)
        .padding(.top, SettingsVisualStyle.sidebarTopPadding)
        .frame(
            minWidth: SettingsVisualStyle.sidebarWidth,
            idealWidth: SettingsVisualStyle.sidebarWidth,
            maxWidth: SettingsVisualStyle.sidebarWidth,
            maxHeight: .infinity
        )
        .background(
            SettingsVisualStyle.sidebarBackground,
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private func rowBackground(for section: SettingsSection) -> Color {
        if selectedSection == section {
            SettingsVisualStyle.selectedBackground
        } else if hoveredSection == section {
            SettingsVisualStyle.hoverBackground
        } else {
            .clear
        }
    }
}
