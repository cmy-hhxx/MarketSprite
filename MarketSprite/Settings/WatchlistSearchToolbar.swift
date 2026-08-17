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
                    Text(primaryActionTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: SettingsVisualStyle.controlFontSize, weight: .medium))
                .foregroundStyle(primaryActionForeground)
                .frame(width: 72, height: SettingsVisualStyle.searchControlHeight)
                .background(primaryActionBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SettingsVisualStyle.separator, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .disabled(isPrimaryActionDisabled)
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

    private var primaryActionTitle: String {
        if searchModel.isSearching {
            "取消"
        } else if searchModel.isPresentingSearch {
            "返回"
        } else {
            "查找"
        }
    }

    private var isPrimaryActionDisabled: Bool {
        !canSubmit && !searchModel.isPresentingSearch
    }

    private var isPrimaryActionProminent: Bool {
        canSubmit && !searchModel.isPresentingSearch
    }

    private var primaryActionForeground: Color {
        isPrimaryActionProminent
            ? .white
            : .secondary.opacity(isPrimaryActionDisabled ? 0.45 : 1)
    }

    private var primaryActionBackground: Color {
        isPrimaryActionProminent ? .accentColor : SettingsVisualStyle.fieldBackground
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
