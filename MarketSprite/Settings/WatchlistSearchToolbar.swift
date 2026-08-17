import SwiftUI

struct WatchlistSearchToolbar: View {
    @ObservedObject var searchModel: WatchlistSearchModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("添加标的")
                .font(
                    .system(size: SettingsVisualStyle.toolbarLabelFontSize, weight: .medium)
                )
                .frame(width: 96, alignment: .leading)

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("名称或代码", text: $searchModel.query)
                        .textFieldStyle(.plain)
                        .font(
                            .system(size: SettingsVisualStyle.controlFontSize, weight: .regular)
                        )
                        .focused($isSearchFocused)
                        .onSubmit(searchModel.submit)

                    if showsClearButton {
                        Button("清除搜索", systemImage: "xmark.circle.fill", action: clearSearch)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .help(tr("清除搜索"))
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: SettingsVisualStyle.searchControlHeight)
                .background(
                    SettingsVisualStyle.fieldBackground,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSearchFocused
                                ? Color.accentColor.opacity(0.72)
                                : SettingsVisualStyle.separator,
                            lineWidth: isSearchFocused ? 1.25 : 1
                        )
                        .allowsHitTesting(false)
                }

                Button(action: performPrimaryAction) {
                    if searchModel.isSearching {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                    } else if searchModel.isPresentingSearch {
                        Text("返回")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("查找")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.regular)
                .tint(canSubmit && !searchModel.isPresentingSearch ? .accentColor : .secondary)
                .frame(width: 72, height: SettingsVisualStyle.searchControlHeight)
                .disabled(!canSubmit && !searchModel.isPresentingSearch)
            }
            .padding(.leading, 16)
        }
        .frame(height: SettingsVisualStyle.searchControlHeight)
        .onExitCommand(perform: cancelSearch)
    }

    private var canSubmit: Bool {
        !searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !searchModel.isSearching
    }

    private var showsClearButton: Bool {
        !searchModel.query.isEmpty
            || !searchModel.results.isEmpty
            || searchModel.message != nil
    }

    private func clearSearch() {
        searchModel.cancel()
        isSearchFocused = true
    }

    private func performPrimaryAction() {
        if searchModel.isPresentingSearch {
            cancelSearch()
        } else {
            searchModel.submit()
        }
    }

    private func cancelSearch() {
        guard !searchModel.query.isEmpty || searchModel.isPresentingSearch else { return }
        searchModel.cancel()
        isSearchFocused = true
    }
}
