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
    @State private var jsonImportText = ""
    @State private var jsonImportMessage: String?
    @State private var showJSONImport = false
    @State private var confirmJSONImport = false
    @State private var removalCandidate: Instrument?

    private let search: (String) async throws -> [Instrument]

    init(search: @escaping (String) async throws -> [Instrument]) {
        self.search = search
    }

    var body: some View {
        let watchlistIDs = Set(store.instruments.map(\.id))

        VStack(alignment: .leading, spacing: 0) {
            if let sourceError = store.sourceError {
                Label(sourceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            WatchlistSearchSection(
                search: search,
                watchlistIDs: watchlistIDs,
                isWatchlistMutating: store.isWatchlistMutating,
                add: store.add
            )

            WatchlistListHeader(
                count: store.instruments.count,
                importAction: openJSONImport
            )

            SettingsVisualStyle.separator
                .frame(height: 1)

            if store.instruments.isEmpty {
                ScrollView {
                    ContentUnavailableView {
                        Label("还没有观察标的", systemImage: "list.star")
                    } description: {
                        Text("从上方搜索并添加，标的会立即出现在桌面行情面板。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            } else {
                List {
                    ForEach(store.instruments) { instrument in
                        WatchlistInstrumentRow(
                            instrument: instrument,
                            quote: store.monitoredInstrument(for: instrument.id)?.quote,
                            showsDivider: instrument.id != store.instruments.last?.id,
                            isMutating: store.isWatchlistMutating,
                            removeAction: { removalCandidate = instrument }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
                .environment(
                    \.defaultMinListRowHeight,
                    SettingsVisualStyle.watchlistRowHeight
                )
            }
        }
        .frame(
            maxWidth: SettingsVisualStyle.contentMaxWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(.horizontal, SettingsVisualStyle.contentHorizontalPadding)
        .sheet(isPresented: $showJSONImport) {
            jsonImportSheet
        }
        .confirmationDialog(
            "移除观察标的？",
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { isPresented in
                    if !isPresented {
                        removalCandidate = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { instrument in
            Button("移除 \(instrument.name)", role: .destructive) {
                Task { await store.remove(instrument) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("移除后会同时删除该标的的价格目标和行情缓存，此操作不可撤销。")
        }
    }

    private func openJSONImport() {
        fillJSONExample(copyToPasteboard: false, announce: false)
        showJSONImport = true
    }

    private var jsonImportSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("批量导入观察列表"))
                    .font(.title2.bold())
                Spacer()
                Button(tr("关闭")) {
                    showJSONImport = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("粘贴 JSON 列表。每项须包含 symbol、name 和 namespace；导入后会替换当前观察列表。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("填入当前列表") {
                    fillJSONExample(copyToPasteboard: false, announce: true)
                }
                Button("复制当前列表") {
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
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
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
                    Label("导入 JSON", systemImage: "square.and.arrow.down")
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
}
