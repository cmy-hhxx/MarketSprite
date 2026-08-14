import AppKit
import SwiftUI

struct WatchlistSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        WatchlistSettingsContent { query in
            try await store.search(query)
        }
    }
}

private struct WatchlistSettingsContent: View {
    @EnvironmentObject private var store: MonitorStore
    @StateObject private var searchModel: WatchlistSearchModel
    @State private var addMessage: String?
    @State private var jsonImportText = ""
    @State private var jsonImportMessage: String?
    @State private var showJSONImport = false
    @State private var confirmJSONImport = false

    init(search: @escaping (String) async throws -> [Instrument]) {
        _searchModel = StateObject(
            wrappedValue: WatchlistSearchModel(search: search)
        )
    }

    var body: some View {
        let watchlistIDs = Set(store.instruments.map(\.id))

        VStack(alignment: .leading, spacing: 24) {
            if let sourceError = store.sourceError {
                Label {
                    Text(sourceError)
                } icon: {
                    BrandIcon(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }

            SettingsGroup("添加标的") {
                SettingsRow {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            Label("名称或代码", systemImage: "magnifyingglass")
                            Spacer(minLength: 16)
                            searchControls
                                .frame(width: 410)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("名称或代码", systemImage: "magnifyingglass")
                            searchControls
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                if let message = searchModel.message {
                    SettingsRowDivider()
                    SettingsRow {
                        statusMessage(message, systemImage: "magnifyingglass")
                    }
                }

                if let addMessage {
                    SettingsRowDivider()
                    SettingsRow {
                        statusMessage(addMessage, systemImage: "checkmark.circle")
                    }
                }

                if !searchModel.results.isEmpty {
                    SettingsRowDivider()
                    SettingsRow {
                        HStack(spacing: 12) {
                            Label("搜索结果", systemImage: "list.bullet")
                            Spacer(minLength: 12)
                            Text("\(searchModel.results.count) 项")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingsRowDivider()
                    searchResults(watchlistIDs: watchlistIDs)
                }
            }

            SettingsGroup("当前观察（\(store.instruments.count)）", action: {
                Button {
                    fillJSONExample(copyToPasteboard: false, announce: false)
                    showJSONImport = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
            }) {
                if store.instruments.isEmpty {
                    ContentUnavailableView {
                        Label("还没有观察标的", systemImage: "list.star")
                    } description: {
                        Text("从上方搜索并添加，标的会立即出现在桌面行情面板。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    watchlist
                }
            }
        }
        .frame(maxWidth: 620, alignment: .topLeading)
        .sheet(isPresented: $showJSONImport) {
            jsonImportSheet
        }
        .onDisappear {
            searchModel.cancel()
        }
    }

    private var searchControls: some View {
        HStack(spacing: 10) {
            TextField("搜索名称或代码", text: $searchModel.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { searchModel.submit() }

            if !searchModel.query.isEmpty
                || !searchModel.results.isEmpty
                || searchModel.message != nil {
                Button {
                    searchModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("清除搜索"))
            }

            Button {
                searchModel.submit()
            } label: {
                if searchModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("搜索")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                searchModel.query.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || searchModel.isSearching
            )
        }
    }

    private func statusMessage(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchResults(watchlistIDs: Set<InstrumentID>) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(searchModel.results) { instrument in
                    HStack(spacing: 12) {
                        instrumentIdentity(instrument)
                        Spacer(minLength: 12)
                        Button(watchlistIDs.contains(instrument.id) ? "已添加" : "添加") {
                            add(instrument)
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 52, alignment: .trailing)
                        .disabled(
                            store.isWatchlistMutating || watchlistIDs.contains(instrument.id)
                        )
                    }
                    .padding(.vertical, 10)

                    if instrument.id != searchModel.results.last?.id {
                        Divider()
                            .overlay(Color.primary.opacity(0.06))
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .frame(maxHeight: 196)
        .scrollIndicators(.never)
        .clipped()
    }

    private var watchlist: some View {
        List {
            ForEach(store.instruments) { instrument in
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .help(tr("拖动排序"))
                    instrumentIdentity(instrument)
                    Spacer(minLength: 12)
                    if let quote = store.monitoredInstrument(for: instrument.id)?.quote {
                        Text(
                            String(
                                format: "%@%.2f%%",
                                quote.changePercent >= 0 ? "+" : "",
                                quote.changePercent
                            )
                        )
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 58, alignment: .trailing)
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
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                .listRowBackground(Color.clear)
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
        .scrollIndicators(.never)
        .frame(height: watchlistHeight)
    }

    private func instrumentIdentity(_ instrument: Instrument) -> some View {
        HStack(spacing: 10) {
            MarketBadge(market: instrument.market)
            VStack(alignment: .leading, spacing: 2) {
                Text(instrument.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var watchlistHeight: CGFloat {
        min(max(CGFloat(store.instruments.count) * 58, 160), 396)
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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            TextEditor(text: $jsonImportText)
                .font(.body.monospaced())
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

    private func add(_ instrument: Instrument) {
        addMessage = nil
        Task {
            let error = await store.add(instrument)
            if let error {
                addMessage = error
            } else {
                addMessage = String(format: tr("已把 %@ 放到桌面"), instrument.name)
            }
        }
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
}
