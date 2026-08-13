import SwiftUI

struct AlertsSettingsPage: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var isRefreshingAlertPrices = false
    @State private var alertPriceMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageTitle(
                title: "牛熊提醒",
                subtitle: store.alertConfiguration.basis == .percentage
                    ? "涨跌幅以昨收为基准，每次越过阈值只提醒一次"
                    : "为每个标的设置小牛价和小熊价，触达目标价格时提醒"
            )

            SettingsCard {
                Toggle(isOn: alertConfigurationBinding(\.isEnabled)) {
                    Label {
                        Text("开启牛熊提醒")
                    } icon: {
                        BrandIcon(systemName: "bell.badge.fill")
                    }
                }
                Divider().opacity(0.5)
                HStack {
                    Label {
                        Text("提醒依据")
                    } icon: {
                        BrandIcon(systemName: "scope")
                    }
                    Spacer()
                    Picker("", selection: alertConfigurationBinding(\.basis)) {
                        ForEach(AlertBasis.allCases) { basis in
                            Text(basis.displayName).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
                Divider().opacity(0.5)
                Group {
                    if store.alertConfiguration.basis == .percentage {
                        thresholdRow(
                            title: "上涨超过",
                            mascotAsset: "BullMascot",
                            value: alertConfigurationBinding(\.risingThreshold),
                            color: .red
                        )
                        Divider().opacity(0.5)
                        thresholdRow(
                            title: "下跌超过",
                            mascotAsset: "BearMascot",
                            value: alertConfigurationBinding(\.fallingThreshold),
                            color: .green
                        )
                    } else {
                        priceAlertControls
                    }
                    Divider().opacity(0.5)
                    opacitySlider(
                        title: "提醒不透明度",
                        icon: "circle.lefthalf.filled",
                        value: $preferences.alertOpacity,
                        range: 0.2...1
                    )
                    Divider().opacity(0.5)
                    Toggle(isOn: $preferences.bullSoundEnabled) {
                        Label {
                            Text("小牛提示音（短促牛叫）")
                        } icon: {
                            BrandIcon(systemName: "speaker.wave.2.fill")
                        }
                    }
                    Divider().opacity(0.5)
                    Toggle(isOn: $preferences.bearSoundEnabled) {
                        Label {
                            Text("小熊提示音（短促吼声）")
                        } icon: {
                            BrandIcon(systemName: "speaker.wave.2.fill")
                        }
                    }
                }
                .disabled(!store.alertConfiguration.isEnabled)
                .opacity(store.alertConfiguration.isEnabled ? 1 : 0.45)
            }

            Text(
                tr(
                    store.alertConfiguration.basis == .percentage
                        ? "标的回到阈值内至少 0.15 个百分点后会重新布防，防止价格在边缘波动时连续弹出。"
                        : "目标价提醒触发后，价格回到目标内侧至少 0.15% 才会重新布防。行情按刷新频率持续更新。"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("预览小牛") { store.testAlert(.rising) }
                    .buttonStyle(.bordered)
                Button("预览小熊") { store.testAlert(.falling) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var priceAlertControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("实时价格与逐标的目标")
                        .fontWeight(.semibold)
                    Text("先刷新实时价，再一键生成目标或手动调整")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refreshAlertPrices(generateTargets: false)
                } label: {
                    if isRefreshingAlertPrices {
                        ProgressView().controlSize(.small)
                    } else {
                        Label {
                            Text("刷新实时价")
                        } icon: {
                            BrandIcon(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(isRefreshingAlertPrices)
                Button("按现价生成目标") {
                    refreshAlertPrices(generateTargets: true)
                }
                .disabled(isRefreshingAlertPrices)
            }

            if let alertPriceMessage {
                Text(alertPriceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.instruments) { instrument in
                        priceAlertRow(for: instrument)
                        if instrument.id != store.instruments.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 230)
        }
    }

    private func priceAlertRow(for instrument: Instrument) -> some View {
        let quote = store.monitoredInstrument(for: instrument.id)?.quote
        let targets = store.priceAlertTargets[instrument.id]
            ?? PriceAlertTargets(risingPrice: nil, fallingPrice: nil)
        let hasLivePrice = (quote?.lastPrice ?? 0) > 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { targets.isEnabled },
                        set: { store.setPriceTargetsEnabled(for: instrument, enabled: $0) }
                    )
                )
                .labelsHidden()
                .disabled(!hasLivePrice && !targets.isEnabled)

                VStack(alignment: .leading, spacing: 2) {
                    Text(instrument.name).fontWeight(.semibold)
                    Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
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
        .padding(.vertical, 9)
    }

    private func priceField(
        title: String,
        mascotAsset: String,
        instrument: Instrument,
        isRising: Bool,
        value: Double
    ) -> some View {
        HStack(spacing: 6) {
            Image(mascotAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            Text(tr(title))
                .font(.caption)
            Text(instrument.market.currencySymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "",
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack {
            Label {
                Text(tr(title))
            } icon: {
                BrandIcon(systemName: icon)
            }
                .frame(width: 160, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func thresholdRow(
        title: String,
        mascotAsset: String,
        value: Binding<Double>,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(mascotAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text(tr(title)).frame(width: 80, alignment: .leading)
            Slider(value: value, in: 0.5...15, step: 0.5)
                .tint(color)
            Text(String(format: "%.1f%%", value.wrappedValue))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }
}
