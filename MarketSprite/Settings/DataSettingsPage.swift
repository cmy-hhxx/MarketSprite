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
        Form {
            Section("行情状态") {
                LabeledContent {
                    Picker("刷新频率", selection: $preferences.refreshInterval) {
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                } label: {
                    Label("刷新频率", systemImage: "arrow.clockwise")
                }

                LabeledContent {
                    Text("腾讯分时 · 东方财富备用")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("数据源", systemImage: "antenna.radiowaves.left.and.right")
                }

                LabeledContent {
                    Text(lastRefreshText)
                        .foregroundStyle(.secondary)
                        .help(lastRefreshFullText)
                } label: {
                    Label("最近刷新", systemImage: "clock")
                }

                LabeledContent {
                    Button {
                        refreshAll()
                    } label: {
                        if isRefreshing {
                            Label("正在刷新…", systemImage: "arrow.clockwise")
                        } else {
                            Label("立即刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRefreshing)
                } label: {
                    Label("行情刷新", systemImage: "arrow.clockwise")
                }
            }

            Section("存储与诊断") {
                LabeledContent {
                    Text("\(store.quoteBarCount.formatted()) 分钟")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Label("缓存分钟数", systemImage: "clock.arrow.circlepath")
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("数据库路径")
                        if didCopyDatabasePath {
                            Label("已复制", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    databasePathText
                }

                LabeledContent {
                    Button("清空…", role: .destructive) {
                        confirmClearQuoteDB = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                } label: {
                    Label("清空行情缓存", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
