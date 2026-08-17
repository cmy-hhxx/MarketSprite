import SwiftUI

struct WatchlistInstrumentIdentity: View {
    let instrument: Instrument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(instrument.name)
                .font(
                    .system(size: SettingsVisualStyle.instrumentNameFontSize, weight: .medium)
                )
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(instrument.symbol)
                    .font(
                        .system(
                            size: SettingsVisualStyle.metadataFontSize,
                            weight: .regular,
                            design: .monospaced
                        )
                    )
                Text(instrument.namespace.displayName)
                    .font(
                        .system(size: SettingsVisualStyle.metadataFontSize, weight: .regular)
                    )
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}
