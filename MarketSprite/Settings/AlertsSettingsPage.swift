import SwiftUI

struct AlertsSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var isRefreshingAlertPrices = false
    @State private var alertPriceMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("提醒规则") {
                SettingsRow {
                    SettingsToggleRow(isOn: alertConfigurationBinding(\.isEnabled)) {
                        Label {
                            Text("开启牛熊提醒")
                        } icon: {
                            BrandIcon(systemName: "bell.badge.fill")
                        }
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    alertBasisRow
                }
                SettingsRowDivider()
                SettingsRow {
                    Group {
                        if store.alertConfiguration.basis == .percentage {
                            VStack(spacing: 0) {
                                thresholdRow(
                                    title: "上涨超过",
                                    mascotAsset: "BullMascot",
                                    value: alertConfigurationBinding(\.risingThreshold),
                                    color: .red
                                )
                                Divider()
                                    .overlay(Color.primary.opacity(0.06))
                                    .padding(.leading, 40)
                                thresholdRow(
                                    title: "下跌超过",
                                    mascotAsset: "BearMascot",
                                    value: alertConfigurationBinding(\.fallingThreshold),
                                    color: .green
                                )
                            }
                        } else {
                            priceAlertControls
                        }
                    }
                    .disabled(!store.alertConfiguration.isEnabled)
                    .opacity(store.alertConfiguration.isEnabled ? 1 : 0.45)
                }
            }

            SettingsGroup("提醒呈现") {
                SettingsRow {
                    opacitySlider(
                        title: "提醒不透明度",
                        icon: "circle.lefthalf.filled",
                        value: $preferences.alertOpacity,
                        range: 0.2...1
                    )
                }
                SettingsRowDivider()
                SettingsRow {
                    SettingsToggleRow(isOn: $preferences.bullSoundEnabled) {
                        Label {
                            Text("小牛提示音")
                        } icon: {
                            BrandIcon(systemName: "speaker.wave.2.fill")
                        }
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    SettingsToggleRow(isOn: $preferences.bearSoundEnabled) {
                        Label {
                            Text("小熊提示音")
                        } icon: {
                            BrandIcon(systemName: "speaker.wave.2.fill")
                        }
                    }
                }
            }

            SettingsGroup("预览") {
                SettingsRow {
                    HStack(spacing: 16) {
                        Label("播放提醒样式", systemImage: "play.circle")
                        Spacer(minLength: 16)
                        HStack(spacing: 10) {
                            previewButton("预览小牛", direction: .rising)
                            previewButton("预览小熊", direction: .falling)
                        }
                    }
                }
            }
        }
    }

    private var alertBasisRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                alertBasisLabel
                Spacer(minLength: 20)
                alertBasisPicker
                    .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 10) {
                alertBasisLabel
                HStack {
                    Spacer(minLength: 0)
                    alertBasisPicker
                        .frame(width: 260)
                }
            }
        }
    }

    private var alertBasisLabel: some View {
        Label {
            Text("提醒依据")
        } icon: {
            BrandIcon(systemName: "scope")
        }
    }

    private var alertBasisPicker: some View {
        Picker("提醒依据", selection: alertConfigurationBinding(\.basis)) {
            ForEach(AlertBasis.allCases) { basis in
                Text(basis.displayName).tag(basis)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var priceAlertControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            priceAlertHeader

            if let alertPriceMessage {
                Text(alertPriceMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            LazyVStack(spacing: 0) {
                ForEach(store.instruments) { instrument in
                    priceAlertRow(for: instrument)
                    if instrument.id != store.instruments.last?.id {
                        Divider()
                            .overlay(Color.primary.opacity(0.06))
                    }
                }
            }
        }
    }

    private var priceAlertHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text("逐标的目标")
                    .fontWeight(.semibold)
                Spacer(minLength: 16)
                priceAlertActions
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("逐标的目标")
                    .fontWeight(.semibold)
                priceAlertActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var priceAlertActions: some View {
        HStack(spacing: 10) {
            Button {
                refreshAlertPrices(generateTargets: false)
            } label: {
                if isRefreshingAlertPrices {
                    ProgressView().controlSize(.small)
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
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
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
                .disabled(!hasLivePrice && !targets.isEnabled)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    Spacer(minLength: 24)
                    risingPriceField(for: instrument, value: targets.risingPrice ?? 0)
                    fallingPriceField(for: instrument, value: targets.fallingPrice ?? 0)
                }

                VStack(alignment: .trailing, spacing: 8) {
                    risingPriceField(for: instrument, value: targets.risingPrice ?? 0)
                    fallingPriceField(for: instrument, value: targets.fallingPrice ?? 0)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .disabled(!targets.isEnabled)
            .opacity(targets.isEnabled ? 1 : 0.42)
        }
        .padding(.vertical, 12)
    }

    private func risingPriceField(for instrument: Instrument, value: Double) -> some View {
        priceField(
            title: "小牛价 ≥",
            mascotAsset: "BullMascot",
            instrument: instrument,
            isRising: true,
            value: value
        )
    }

    private func fallingPriceField(for instrument: Instrument, value: Double) -> some View {
        priceField(
            title: "小熊价 ≤",
            mascotAsset: "BearMascot",
            instrument: instrument,
            isRising: false,
            value: value
        )
    }

    private func priceField(
        title: String,
        mascotAsset: String,
        instrument: Instrument,
        isRising: Bool,
        value: Double
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(mascotAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(tr(title))
                    .font(.callout)
            }
            Spacer(minLength: 10)
            Text(instrument.market.currencySymbol)
                .font(.callout)
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
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 92)
        }
        .frame(width: 220, alignment: .trailing)
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
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Label(title, systemImage: icon)
                Spacer(minLength: 20)
                Slider(value: value, in: range)
                    .frame(width: 260)
                opacityValue(value)
            }

            HStack(spacing: 12) {
                Label(title, systemImage: icon)
                Spacer(minLength: 8)
                Slider(value: value, in: range)
                    .frame(minWidth: 92, idealWidth: 132, maxWidth: 156)
                opacityValue(value)
            }
        }
    }

    private func opacityValue(_ value: Binding<Double>) -> some View {
        Text("\(Int(value.wrappedValue * 100))%")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
    }

    private func thresholdRow(
        title: String,
        mascotAsset: String,
        value: Binding<Double>,
        color: Color
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                thresholdLabel(title: title, mascotAsset: mascotAsset)
                Spacer(minLength: 20)
                thresholdSlider(value: value, color: color)
                    .frame(width: 260)
                thresholdValue(value)
            }

            HStack(spacing: 10) {
                thresholdLabel(title: title, mascotAsset: mascotAsset)
                Spacer(minLength: 8)
                thresholdSlider(value: value, color: color)
                    .frame(minWidth: 92, idealWidth: 132, maxWidth: 156)
                thresholdValue(value)
            }
        }
        .padding(.vertical, 8)
    }

    private func thresholdLabel(title: String, mascotAsset: String) -> some View {
        HStack(spacing: 8) {
            Image(mascotAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text(tr(title))
        }
    }

    private func thresholdSlider(value: Binding<Double>, color: Color) -> some View {
        Slider(value: value, in: 0.5...15, step: 0.5)
            .tint(color)
    }

    private func thresholdValue(_ value: Binding<Double>) -> some View {
        Text(String(format: "%.1f%%", value.wrappedValue))
            .font(.body.weight(.semibold).monospacedDigit())
            .frame(width: 52, alignment: .trailing)
    }

    private func previewButton(_ title: String, direction: AlertDirection) -> some View {
        Button {
            store.testAlert(direction)
        } label: {
            Label(title, systemImage: "speaker.wave.2")
        }
        .buttonStyle(.bordered)
    }
}
