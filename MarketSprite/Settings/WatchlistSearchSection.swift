import SwiftUI

struct WatchlistSearchSection: View {
    let watchlistIDs: Set<InstrumentID>
    let isWatchlistMutating: Bool
    let add: (Instrument) async -> String?

    @StateObject private var searchModel: WatchlistSearchModel
    @State private var addMessage: String?

    init(
        search: @escaping (String) async throws -> [Instrument],
        watchlistIDs: Set<InstrumentID>,
        isWatchlistMutating: Bool,
        add: @escaping (Instrument) async -> String?
    ) {
        _searchModel = StateObject(wrappedValue: WatchlistSearchModel(search: search))
        self.watchlistIDs = watchlistIDs
        self.isWatchlistMutating = isWatchlistMutating
        self.add = add
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WatchlistSearchToolbar(searchModel: searchModel)
                .padding(.bottom, 16)

            SettingsVisualStyle.separator
                .frame(height: 1)

            if let message = searchModel.message {
                Label(message, systemImage: "magnifyingglass")
                    .font(.system(size: SettingsVisualStyle.controlFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
            }

            if let addMessage {
                Label(addMessage, systemImage: "checkmark.circle")
                    .font(.system(size: SettingsVisualStyle.controlFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
            }

            if !searchModel.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("找到 \(searchModel.results.count) 个结果")
                        .font(
                            .system(
                                size: SettingsVisualStyle.listHeaderFontSize,
                                weight: .medium
                            )
                            .monospacedDigit()
                        )
                        .foregroundStyle(.secondary)
                        .frame(height: 36)

                    ForEach(searchModel.results) { instrument in
                        HStack(spacing: 12) {
                            WatchlistInstrumentIdentity(instrument: instrument)
                            Spacer(minLength: 12)
                            Button(watchlistIDs.contains(instrument.id) ? "已添加" : "添加") {
                                addInstrument(instrument)
                            }
                            .buttonStyle(.borderless)
                            .disabled(
                                isWatchlistMutating || watchlistIDs.contains(instrument.id)
                            )
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onChange(of: searchModel.query) { _, _ in
            addMessage = nil
        }
        .onDisappear {
            searchModel.cancel()
        }
    }

    private func addInstrument(_ instrument: Instrument) {
        addMessage = nil
        Task {
            if let error = await add(instrument) {
                addMessage = error
                return
            }

            let message = String(format: tr("已把 %@ 放到桌面"), instrument.name)
            addMessage = message
            try? await Task.sleep(for: .seconds(3))
            if addMessage == message {
                addMessage = nil
            }
        }
    }
}
