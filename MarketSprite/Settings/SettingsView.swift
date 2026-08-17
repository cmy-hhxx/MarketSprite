import OSLog
import SwiftUI

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .watchlist
    @State private var hasLoadedQuoteBarCount = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedSection: $selectedSection)

            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(section: selectedSection)
                    .padding(.horizontal, SettingsVisualStyle.contentHorizontalPadding)
                    .padding(.top, 36)
                    .padding(.bottom, selectedSection == .watchlist ? 24 : 16)

                SettingsDetailView(
                    section: selectedSection,
                    hasLoadedQuoteBarCount: $hasLoadedQuoteBarCount
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SettingsVisualStyle.contentBackground)
        }
        .background(SettingsVisualStyle.contentBackground)
        .font(.system(size: SettingsVisualStyle.controlFontSize))
        .ignoresSafeArea(edges: .top)
        .onAppear {
            let interval = SettingsSignposts.signposter.beginInterval(
                "SettingsOpen",
                id: SettingsSignposts.signposter.makeSignpostID()
            )
            DispatchQueue.main.async {
                SettingsSignposts.signposter.endInterval("SettingsOpen", interval)
            }
        }
        .onChange(of: selectedSection) { _, section in
            let interval = SettingsSignposts.signposter.beginInterval(
                "SettingsSectionChange",
                id: SettingsSignposts.signposter.makeSignpostID()
            )
            DispatchQueue.main.async {
                SettingsSignposts.signposter.endInterval("SettingsSectionChange", interval)
            }
            _ = section
        }
    }
}

private enum SettingsSignposts {
    static let signposter = OSSignposter(
        subsystem: "io.github.cmy-hhxx.marketsprite",
        category: "Settings"
    )
}

struct SettingsDetailView: View {
    let section: SettingsSection
    @Binding var hasLoadedQuoteBarCount: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsStorageErrorBanner()

            switch section {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsVisualStyle.contentBackground)
    }
}

struct SettingsStorageErrorBanner: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        if let message = store.storageError {
            HStack(alignment: .top, spacing: 8) {
                Label(message, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Button(tr("关闭"), systemImage: "xmark.circle.fill") {
                    store.dismissStorageError()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("关闭"))
            }
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, SettingsVisualStyle.contentHorizontalPadding)
            .padding(.top, 12)
        }
    }
}

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
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

    var iconTint: Color {
        switch self {
        case .watchlist:
            Color(red: 0.57, green: 0.58, blue: 0.61)
        case .appearance:
            Color(red: 0.36, green: 0.32, blue: 0.88)
        case .alerts:
            Color(red: 0.96, green: 0.25, blue: 0.30)
        case .data:
            Color(red: 0.03, green: 0.69, blue: 0.72)
        }
    }
}
