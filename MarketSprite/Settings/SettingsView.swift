import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var selectedSection: SettingsSection = .watchlist

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    BrandIcon(systemName: section.icon)
                }
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 168, max: 190)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if let storageError = store.storageError {
                    storageErrorBanner(storageError)
                }

                switch selectedSection {
                case .watchlist:
                    WatchlistSettingsPage()
                case .appearance:
                    SettingsScrollView {
                        AppearanceSettingsPage()
                            .frame(maxWidth: 640, alignment: .topLeading)
                    }
                case .alerts:
                    SettingsScrollView {
                        AlertsSettingsPage()
                            .frame(maxWidth: 640, alignment: .topLeading)
                    }
                case .data:
                    SettingsScrollView {
                        DataSettingsPage()
                            .frame(maxWidth: 640, alignment: .topLeading)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("\(AppIdentity.displayName) 设置")
        .toolbar(removing: .sidebarToggle)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .textSelection(.enabled)
    }

    private func storageErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Label {
                Text(message)
            } icon: {
                BrandIcon(systemName: "externaldrive.badge.exclamationmark")
            }
                .font(.caption)
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
