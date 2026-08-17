import SwiftUI

struct AlertsSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var isRefreshingAlertPrices = false
    @State private var alertPriceMessage: String?

    var body: some View {
        Form {
            Section("提醒规则") {
                Toggle(isOn: alertConfigurationBinding(\.isEnabled)) {
                    Label("开启牛熊提醒", systemImage: "bell.badge.fill")
                }

                LabeledContent {
                    Picker("提醒依据", selection: alertConfigurationBinding(\.basis)) {
                        ForEach(AlertBasis.allCases) { basis in
                            Text(basis.displayName).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                } label: {
                    Label("提醒依据", systemImage: "scope")
                }

                Group {
                    if store.alertConfiguration.basis == .percentage {
                        VStack(spacing: 10) {
                            thresholdRow(
                                title: "上涨超过",
                                mascotAsset: "BullMascot",
                                value: alertConfigurationBinding(\.risingThreshold),
                                color: BrandPalette.coral
                            )
                            thresholdRow(
                                title: "下跌超过",
                                mascotAsset: "BearMascot",
                                value: alertConfigurationBinding(\.fallingThreshold),
                                color: BrandPalette.mint
                            )
                        }
                    } else {
                        priceAlertControls
                    }
                }
                .disabled(!store.alertConfiguration.isEnabled)
                .opacity(store.alertConfiguration.isEnabled ? 1 : 0.45)
            }

            Section("提醒呈现") {
                LabeledContent {
                    opacitySlider(value: $preferences.alertOpacity, range: 0.2...1)
                } label: {
                    Label("提醒不透明度", systemImage: "circle.lefthalf.filled")
                }

                Toggle(isOn: $preferences.bullSoundEnabled) {
                    Label("小牛提示音", systemImage: "speaker.wave.2.fill")
                }

                Toggle(isOn: $preferences.bearSoundEnabled) {
                    Label("小熊提示音", systemImage: "speaker.wave.2.fill")
                }
            }

            Section("预览") {
                LabeledContent {
                    HStack(spacing: 10) {
                        previewButton("预览小牛", direction: .rising)
                        previewButton("预览小熊", direction: .falling)
                    }
                } label: {
                    Label("播放提醒样式", systemImage: "play.circle")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var priceAlertControls: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("逐标的目标")
                    .font(.headline)
                Spacer(minLength: 12)
                priceAlertActions
            }

            if let alertPriceMessage {
                Text(alertPriceMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            ForEach(store.instruments) { instrument in
                priceAlertRow(for: instrument)
            }
        }
    }

    private var priceAlertActions: some View {
        HStack(spacing: 10) {
            Button {
                refreshAlertPrices(generateTargets: false)
            } label: {
                if isRefreshingAlertPrices {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新实时价", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshingAlertPrices)

            Button("按现价生成目标") {
                refreshAlertPrices(generateTargets: true)
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshingAlertPrices)
        }
    }

    private func priceAlertRow(for instrument: Instrument) -> some View {
        let quote = store.monitoredInstrument(for: instrument.id)?.quote
        let targets = store.priceAlertTargets[instrument.id]
            ?? PriceAlertTargets(risingPrice: nil, fallingPrice: nil)
        let hasLivePrice = (quote?.lastPrice ?? 0) > 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instrument.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let quote {
                    Text(
                        String(
                            format: tr("现价 %@%.2f"),
                            instrument.market.currencySymbol,
                            quote.lastPrice
                        )
                    )
                    .font(.body.bold().monospacedDigit())
                } else {
                    Text("等待实时价")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "",
                    isOn: Binding(
                        get: { targets.isEnabled },
                        set: { store.setPriceTargetsEnabled(for: instrument, enabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
                .disabled(!hasLivePrice && !targets.isEnabled)
                .accessibilityLabel(tr("\(instrument.name) 目标价格提醒"))
                .accessibilityValue(targets.isEnabled ? tr("已开启") : tr("已关闭"))
                .accessibilityHint(
                    hasLivePrice
                        ? tr("开启后可设置上涨和下跌目标价格")
                        : tr("等待实时价格后才能开启")
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                priceField(
                    title: "小牛价 ≥",
                    mascotAsset: "BullMascot",
                    instrument: instrument,
                    isRising: true,
                    value: targets.risingPrice ?? 0
                )
                priceField(
                    title: "小熊价 ≤",
                    mascotAsset: "BearMascot",
                    instrument: instrument,
                    isRising: false,
                    value: targets.fallingPrice ?? 0
                )
            }
            .disabled(!targets.isEnabled)
            .opacity(targets.isEnabled ? 1 : 0.42)
        }
        .padding(.vertical, 8)
    }

    private func priceField(
        title: String,
        mascotAsset: String,
        instrument: Instrument,
        isRising: Bool,
        value: Double
    ) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(instrument.market.currencySymbol)
                    .foregroundStyle(.secondary)
                TextField(
                    title,
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            let current = store.priceAlertTargets[instrument.id]
                                ?? PriceAlertTargets(risingPrice: nil, fallingPrice: nil)
                            store.updatePriceTargets(
                                for: instrument,
                                risingPrice: isRising ? newValue : current.risingPrice,
                                fallingPrice: isRising ? current.fallingPrice : newValue
                            )
                        }
                    ),
                    format: .number.precision(.fractionLength(2))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 92)
            }
        } label: {
            HStack(spacing: 8) {
                Image(mascotAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(title)
            }
        }
    }

    private func refreshAlertPrices(generateTargets: Bool) {
        isRefreshingAlertPrices = true
        alertPriceMessage = nil
        Task {
            await store.refreshAll()
            if generateTargets {
                let count = store.generatePriceTargetsFromCurrentQuotes()
                alertPriceMessage = String(
                    format: tr("已按当前价为 %d 个标的生成目标"),
                    count
                )
            } else {
                alertPriceMessage = tr("实时价格已刷新")
            }
            isRefreshingAlertPrices = false
        }
    }

    private func alertConfigurationBinding<Value>(
        _ keyPath: WritableKeyPath<AlertConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.alertConfiguration[keyPath: keyPath] },
            set: { value in
                var configuration = store.alertConfiguration
                configuration[keyPath: keyPath] = value
                store.updateAlertConfiguration(configuration)
            }
        )
    }

    private func opacitySlider(
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: range)
                .tint(.accentColor)
                .controlSize(.small)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .frame(minWidth: 180, idealWidth: 280, maxWidth: 360)
    }

    private func thresholdRow(
        title: String,
        mascotAsset: String,
        value: Binding<Double>,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(mascotAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text(title)
            }

            Slider(value: value, in: 0.5...15, step: 0.5)
                .tint(color)

            Text(String(format: "%.1f%%", value.wrappedValue))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func previewButton(_ title: String, direction: AlertDirection) -> some View {
        Button {
            store.testAlert(direction)
        } label: {
            Label(title, systemImage: "speaker.wave.2")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
