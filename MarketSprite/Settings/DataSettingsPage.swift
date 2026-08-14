import AppKit
import SwiftUI

struct DataSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var hasLoadedQuoteBarCount: Bool
    @State private var confirmClearQuoteDB = false
    @State private var isRefreshing = false
    @State private var didCopyDatabasePath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard {
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
                    HStack(spacing: 12) {
                        Text("数据源")
                        Text(tr("腾讯分时 · 东方财富备用"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 12) {
                        Text("最近刷新")
                        Text(lastRefreshText)
                            .foregroundStyle(.secondary)
                            .help(lastRefreshFullText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 12) {
                        Text("行情刷新")

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
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            SettingsGroup("本地缓存") {
                SettingsRow {
                    HStack(spacing: 12) {
                        Text("缓存分钟数")
                        Text("\(store.quoteBarCount.formatted()) 分钟")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                SettingsRowDivider()
                SettingsRow {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text("数据库路径")
                            if didCopyDatabasePath {
                                Label("已复制", systemImage: "checkmark")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                        }
                        databasePathText
                            .frame(minWidth: 0, maxWidth: 400, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 12) {
                        Text("清空行情缓存")

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
                    .frame(maxWidth: .infinity, alignment: .center)
                }
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
                .multilineTextAlignment(.center)
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
