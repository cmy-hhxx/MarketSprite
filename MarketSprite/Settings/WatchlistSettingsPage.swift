import AppKit
import SwiftUI

struct WatchlistSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var query = ""
    @State private var results: [Instrument] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var jsonImportText = ""
    @State private var jsonImportMessage: String?
    @State private var showJSONImport = false
    @State private var confirmJSONImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPageTitle(
                title: "观察列表",
                subtitle: "搜索名称或代码，也可通过 JSON 批量导入"
            )

            if let sourceError = store.sourceError {
                Label {
                    Text(sourceError)
                } icon: {
                    BrandIcon(systemName: "exclamationmark.triangle.fill")
                }
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                TextField("例如：贵州茅台、00700、AAPL", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }

                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("搜索")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSearching
                )

                Button {
                    fillJSONExample(copyToPasteboard: false, announce: false)
                    showJSONImport = true
                } label: {
                    Text("JSON 导入")
                }
                .buttonStyle(.bordered)
            }

            if let searchMessage {
                Text(searchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !results.isEmpty {
                searchResults
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(tr("当前")) \(store.instruments.count) \(tr("个"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.instruments.isEmpty {
                    Text("拖动排序")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)

            if store.instruments.isEmpty {
                Text(tr("还没有标的，搜索名称或代码后添加"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                    .background(
                        Color.primary.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            } else {
                watchlist
            }
        }
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showJSONImport) {
            jsonImportSheet
        }
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(results) { instrument in
                HStack(spacing: 10) {
                    MarketBadge(market: instrument.market)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instrument.name).fontWeight(.medium)
                        Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(
                        tr(
                            store.instruments.contains(where: { $0.id == instrument.id })
                                ? "已添加"
                                : "添加"
                        )
                    ) {
                        Task {
                            searchMessage = await store.add(instrument)
                            if searchMessage == nil {
                                searchMessage = String(
                                    format: tr("已把 %@ 放到桌面"),
                                    instrument.name
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        store.isWatchlistMutating
                            || store.instruments.contains(where: { $0.id == instrument.id })
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if instrument.id != results.last?.id {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .frame(maxHeight: 148)
    }

    private var watchlist: some View {
        List {
            ForEach(store.instruments) { instrument in
                HStack(spacing: 10) {
                    MarketBadge(market: instrument.market)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instrument.name).fontWeight(.medium)
                        Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let quote = store.monitoredInstrument(for: instrument.id)?.quote {
                        Text(
                            String(
                                format: "%@%.2f%%",
                                quote.changePercent >= 0 ? "+" : "",
                                quote.changePercent
                            )
                        )
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            instrument.market.colorRole(
                                isRising: quote.changePercent >= 0
                            ).color
                        )
                    }
                    Button(role: .destructive) {
                        Task { await store.remove(instrument) }
                    } label: {
                        BrandIcon(systemName: "trash", size: 11, showsBackground: false)
                    }
                    .buttonStyle(.borderless)
                    .help(tr("删除"))
                    .disabled(store.isWatchlistMutating)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .listRowSeparator(.visible)
                .moveDisabled(store.isWatchlistMutating)
            }
            .onMove { offsets, destination in
                Task {
                    await store.moveInstruments(from: offsets, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jsonImportSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("通过 JSON 导入"))
                    .font(.title2.bold())
                Spacer()
                Button(tr("关闭")) {
                    showJSONImport = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("必填：symbol、name、namespace（sse / szse / bse / hk / us）。导入将替换当前观察列表。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("填入当前示例") {
                    fillJSONExample(copyToPasteboard: false, announce: true)
                }
                Button("复制到剪贴板") {
                    fillJSONExample(copyToPasteboard: true, announce: true)
                }
                Spacer()
                if let jsonImportMessage {
                    Text(jsonImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            TextEditor(text: $jsonImportText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    Color.secondary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button {
                    if store.instruments.isEmpty {
                        applyJSONImport()
                    } else {
                        confirmJSONImport = true
                    }
                } label: {
                    Label {
                        Text("导入 JSON")
                    } icon: {
                        BrandIcon(systemName: "square.and.arrow.down")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImportJSON || store.isWatchlistMutating)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .confirmationDialog(
            tr("用 JSON 替换当前观察列表？"),
            isPresented: $confirmJSONImport,
            titleVisibility: .visible
        ) {
            Button(tr("替换并导入"), role: .destructive) {
                applyJSONImport()
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: tr("当前有 %d 个标的，导入后将被 JSON 中的列表替换，此操作不可撤销。"),
                    store.instruments.count
                )
            )
        }
    }

    private var canImportJSON: Bool {
        let trimmed = jsonImportText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "[]"
    }

    private func applyJSONImport() {
        Task {
            let result = await store.importWatchlist(fromJSON: jsonImportText)
            jsonImportMessage = result.message
            if case .success = result {
                showJSONImport = false
            }
        }
    }

    private func fillJSONExample(copyToPasteboard: Bool, announce: Bool) {
        let example = store.watchlistJSONExample()
        jsonImportText = example
        if copyToPasteboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(example, forType: .string)
        }
        guard announce else {
            jsonImportMessage = nil
            return
        }
        jsonImportMessage = tr(
            copyToPasteboard ? "已填入编辑框并复制到剪贴板" : "已填入当前观察列表示例"
        )
    }

    private func runSearch() {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        results = []

        Task {
            do {
                let found = try await store.search(cleanQuery)
                results = found
                searchMessage = found.isEmpty ? tr("没有找到支持的 A股、港股或美股") : nil
            } catch {
                searchMessage = String(
                    format: tr("搜索失败：%@"),
                    error.localizedDescription
                )
            }
            isSearching = false
        }
    }
}
