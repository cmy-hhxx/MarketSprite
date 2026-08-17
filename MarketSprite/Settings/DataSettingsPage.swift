import AppKit
import SwiftUI

struct DataSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var hasLoadedQuoteBarCount: Bool
    @State private var confirmClearQuoteDB = false
    @State private var isRefreshing = false
    @State private var didCopyDatabasePath = false
    @State private var showsStorageDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("行情状态") {
                SettingsRow {
                    HStack(spacing: 16) {
                        Label("刷新频率", systemImage: "arrow.clockwise")

                        Spacer(minLength: 16)

                        Picker("刷新频率", selection: $preferences.refreshInterval) {
                            Text("15 秒").tag(15)
                            Text("30 秒").tag(30)
                            Text("60 秒").tag(60)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 16) {
                        Label("数据源", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer(minLength: 16)
                        Text(tr("腾讯分时 · 东方财富备用"))
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 16) {
                        Label("最近刷新", systemImage: "clock")
                        Spacer(minLength: 16)
                        Text(lastRefreshText)
                            .foregroundStyle(.secondary)
                            .help(lastRefreshFullText)
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 16) {
                        Label("行情刷新", systemImage: "arrow.clockwise")
                        Spacer(minLength: 16)

                        Button {
                            refreshAll()
                        } label: {
                            if isRefreshing {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("正在刷新…")
                                }
                            } else {
                                Label("立即刷新", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRefreshing)
                    }
                }
            }

            SettingsGroup("存储与诊断") {
                DisclosureGroup(isExpanded: $showsStorageDiagnostics) {
                    VStack(spacing: 0) {
                        SettingsRow {
                            HStack(spacing: 16) {
                                Label("缓存分钟数", systemImage: "clock.arrow.circlepath")
                                Spacer(minLength: 16)
                                Text("\(store.quoteBarCount.formatted()) 分钟")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        SettingsRowDivider()
                        SettingsRow {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("数据库路径")
                                    if didCopyDatabasePath {
                                        Label("已复制", systemImage: "checkmark")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(BrandPalette.mintInk)
                                    }
                                }
                                databasePathText
                            }
                        }
                        SettingsRowDivider()
                        SettingsRow {
                            HStack(spacing: 16) {
                                Label("清空行情缓存", systemImage: "trash")
                                Spacer(minLength: 16)

                                Button(role: .destructive) {
                                    confirmClearQuoteDB = true
                                } label: {
                                    Label("清空…", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .confirmationDialog(
                                    tr("清空全部行情缓存？此操作不可撤销。"),
                                    isPresented: $confirmClearQuoteDB,
                                    titleVisibility: .visible
                                ) {
                                    Button(tr("清空"), role: .destructive) {
                                        Task {
                                            await store.clearQuoteHistory()
                                            await store.refreshQuoteBarCount()
                                        }
                                    }
                                    Button(tr("取消"), role: .cancel) {}
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("显示缓存、路径与清理操作", systemImage: "externaldrive")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            }
        }
        .task {
            guard !hasLoadedQuoteBarCount else { return }
            hasLoadedQuoteBarCount = true
            await store.refreshQuoteBarCount()
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh = store.lastRefresh else { return tr("尚未连接") }
        return lastRefresh.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                calendar: .current,
                timeZone: .current
            )
            .locale(Locale(identifier: "zh_CN"))
        )
    }

    private var lastRefreshFullText: String {
        guard let lastRefresh = store.lastRefresh else { return tr("尚未连接") }
        return lastRefresh.formatted(
            Date.FormatStyle(
                date: .long,
                time: .standard,
                calendar: .current,
                timeZone: .current
            )
            .locale(Locale(identifier: "zh_CN"))
        )
    }

    private var databasePathText: some View {
        Button {
            copyDatabasePath()
        } label: {
            Text(store.databasePath.isEmpty ? tr("未打开") : store.databasePath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(store.databasePath.isEmpty)
        .help(store.databasePath.isEmpty ? tr("未打开") : tr("点击复制完整数据库路径"))
        .accessibilityLabel(tr("数据库路径"))
        .accessibilityValue(store.databasePath)
        .accessibilityHint(tr("点击复制路径"))
    }

    private func copyDatabasePath() {
        guard !store.databasePath.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.databasePath, forType: .string)
        didCopyDatabasePath = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyDatabasePath = false
        }
    }

    private func refreshAll() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            await store.refreshAll()
            await store.refreshQuoteBarCount()
        }
    }
}
