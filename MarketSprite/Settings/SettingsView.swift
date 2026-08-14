import SwiftUI

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .watchlist
    @State private var hasLoadedQuoteBarCount = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedSection: $selectedSection)
            Divider()
                .overlay(Color.primary.opacity(0.06))

            SettingsScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsPageHeader(section: selectedSection)
                    SettingsStorageErrorBanner()

                    switch selectedSection {
                    case .watchlist:
                        WatchlistSettingsPage()
                    case .appearance:
                        AppearanceSettingsPage()
                    case .alerts:
                        AlertsSettingsPage()
                    case .data:
                        DataSettingsPage(hasLoadedQuoteBarCount: $hasLoadedQuoteBarCount)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .textSelection(.enabled)
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label {
                        Text(section.title)
                            .font(.body.weight(.semibold))
                    } icon: {
                        BrandIcon(
                            systemName: section.icon,
                            tint: selectedSection == section ? BrandPalette.mint : .secondary
                        )
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BrandPalette.mint.opacity(0.22))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .frame(
            minWidth: 184,
            idealWidth: 184,
            maxWidth: 184,
            maxHeight: .infinity
        )
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }
}

private struct SettingsPageHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 12) {
            BrandIcon(systemName: section.icon, size: 18, tint: BrandPalette.mint)
            Text(section.title)
                .font(.title2.weight(.semibold))
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsStorageErrorBanner: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        if let message = store.storageError {
        HStack(alignment: .top, spacing: 8) {
            Label {
                Text(message)
            } icon: {
                BrandIcon(systemName: "externaldrive.badge.exclamationmark")
            }
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                store.dismissStorageError()
            } label: {
                BrandIcon(systemName: "xmark.circle.fill", size: 11, showsBackground: false)
            }
            .buttonStyle(.plain)
            .help(tr("关闭"))
        }
            .padding(10)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case watchlist
    case appearance
    case alerts
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchlist: tr("观察列表")
        case .appearance: tr("外观与交互")
        case .alerts: tr("牛熊提醒")
        case .data: tr("数据与刷新")
        }
    }

    var icon: String {
        switch self {
        case .watchlist: "list.star"
        case .appearance: "paintbrush"
        case .alerts: "bell.badge"
        case .data: "network"
        }
    }
}
