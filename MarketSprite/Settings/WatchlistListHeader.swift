import SwiftUI

struct WatchlistListHeader: View {
    let count: Int
    let importAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(count) 个标的")
                .font(
                    .system(size: SettingsVisualStyle.listHeaderFontSize, weight: .medium)
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 12)

            Button("批量导入…", systemImage: "square.and.arrow.down", action: importAction)
                .font(
                    .system(size: SettingsVisualStyle.listHeaderFontSize, weight: .regular)
                )
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("批量导入观察列表"))
        }
        .frame(height: SettingsVisualStyle.listHeaderHeight)
    }
}
