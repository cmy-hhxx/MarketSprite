import SwiftUI

struct DataSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var confirmClearQuoteDB = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageTitle(title: "数据与刷新")

            SettingsCard {
                HStack {
                    Label {
                        Text("刷新频率")
                    } icon: {
                        BrandIcon(systemName: "arrow.clockwise")
                    }
                    Spacer()
                    Picker("", selection: $preferences.refreshInterval) {
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Divider().opacity(0.5)
                LabeledContent("当前数据源", value: tr("腾讯分时 · 东方财富备用"))
                Divider().opacity(0.5)
                LabeledContent(
                    "最近刷新",
                    value: store.lastRefresh?.formatted(
                        Date.FormatStyle(
                            date: .abbreviated,
                            time: .standard,
                            calendar: .current,
                            timeZone: .current
                        )
                    ) ?? tr("尚未连接")
                )
            }

            SettingsCard {
                LabeledContent("分钟行情库行数", value: "\(store.quoteBarCount)")
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("库路径"))
                        .font(.subheadline.weight(.semibold))
                    Text(store.databasePath.isEmpty ? tr("未打开") : store.databasePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider().opacity(0.5)
                Button(role: .destructive) {
                    confirmClearQuoteDB = true
                } label: {
                    Label {
                        Text("清空行情库")
                    } icon: {
                        BrandIcon(systemName: "trash")
                    }
                }
                .confirmationDialog(
                    tr("清空全部已存分钟行情？此操作不可撤销。"),
                    isPresented: $confirmClearQuoteDB,
                    titleVisibility: .visible
                ) {
                    Button(tr("清空"), role: .destructive) {
                        Task { await store.clearQuoteHistory() }
                    }
                    Button(tr("取消"), role: .cancel) {}
                }
            }

            Button {
                Task {
                    await store.refreshAll()
                    await store.refreshQuoteBarCount()
                }
            } label: {
                Label {
                    Text("立即刷新全部标的")
                } icon: {
                    BrandIcon(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 8) {
                Text("使用说明")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 本应用仅用于个人辅助查看，不构成投资建议。")
                    Text("• 公开网页行情可能延迟、限流或调整，不应用于下单决策。")
                    Text("• 港股、美股实时权限受交易所授权约束；若需要交易级数据，可后续接入富途 OpenD 或券商行情。")
                    Text("• 接口失败时不会生成假曲线，只保留最后一次成功数据并标记为过期。")
                    Text("• A 股收盘后复盘标记：S 为最高分钟收盘价，B 仅标注随后出现上涨的最低分钟收盘价；不构成交易建议。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .task {
            await store.refreshQuoteBarCount()
        }
    }
}
