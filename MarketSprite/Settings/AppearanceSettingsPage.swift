import SwiftUI

struct AppearanceSettingsPage: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var loginItem: LoginItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup("显示效果") {
                SettingsRow {
                    slider(
                        title: "整体大小",
                        icon: "arrow.up.left.and.arrow.down.right",
                        value: $preferences.displayScale,
                        range: 0.65...1.6,
                        step: 0.05
                    )
                }
                SettingsRowDivider()
                SettingsRow {
                    slider(
                        title: "曲线不透明度",
                        icon: "waveform.path.ecg",
                        value: $preferences.lineOpacity,
                        range: 0.15...1
                    )
                }
                SettingsRowDivider()
                SettingsRow {
                    slider(
                        title: "名称与数字不透明度",
                        icon: "textformat",
                        value: $preferences.labelOpacity,
                        range: 0.72...1
                    )
                }
                SettingsRowDivider()
                SettingsRow {
                    slider(
                        title: "背景板不透明度",
                        icon: "square.on.square",
                        value: $preferences.backgroundOpacity,
                        range: 0...1
                    )
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack(spacing: 16) {
                        Label("默认外观", systemImage: "arrow.counterclockwise")
                        Spacer(minLength: 16)
                        Button("恢复默认") {
                            preferences.resetAppearance()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            SettingsGroup("窗口行为") {
                SettingsRow {
                    SettingsToggleRow(isOn: $preferences.compactMode) {
                        Label("紧凑模式", systemImage: "rectangle.compress.vertical")
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    SettingsToggleRow(isOn: $preferences.alwaysOnTop) {
                        Label("始终置顶", systemImage: "pin.fill")
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    SettingsToggleRow(
                        isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { loginItem.setEnabled($0) }
                        )
                    ) {
                        Label("登录时自动启动", systemImage: "power")
                    }
                    .disabled(loginItem.isUpdating)
                }
                if let message = loginItem.message {
                    SettingsRowDivider()
                    SettingsRow {
                        HStack(spacing: 12) {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            if loginItem.requiresApproval {
                                Button("打开登录项设置") {
                                    loginItem.openSystemSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    SettingsToggleRow(isOn: $preferences.clickThrough) {
                        Label("鼠标穿透（从菜单栏恢复）", systemImage: "cursorarrow.slash")
                    }
                    .help(tr("开启后，请从菜单栏图标关闭鼠标穿透。"))
                }
            }

            SettingsGroup("快捷键") {
                SettingsRow {
                    SettingsToggleRow(isOn: $preferences.shortcutEnabled) {
                        Label("显示/隐藏行情面板", systemImage: "keyboard")
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    HStack {
                        Text("按键组合")
                        Spacer()
                        Picker("修饰键", selection: $preferences.shortcutModifier) {
                            ForEach(ShortcutModifierOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 86)

                        Text("+")
                            .foregroundStyle(.secondary)

                        Picker("按键", selection: $preferences.shortcutKey) {
                            ForEach(ShortcutKeyOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 78)
                    }
                }
                .disabled(!preferences.shortcutEnabled)
                .opacity(preferences.shortcutEnabled ? 1 : 0.45)
            }
        }
    }

    private func slider(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                Label(title, systemImage: icon)
                    .frame(width: 172, alignment: .leading)
                sliderControl(value: value, range: range, step: step)
                    .frame(minWidth: 140, maxWidth: .infinity)
                sliderValue(value)
            }

            HStack(spacing: 12) {
                Label(title, systemImage: icon)
                sliderControl(value: value, range: range, step: step)
                    .frame(minWidth: 92, idealWidth: 132, maxWidth: .infinity)
                sliderValue(value)
            }
        }
    }

    @ViewBuilder
    private func sliderControl(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double?
    ) -> some View {
        if let step {
            Slider(value: snappedBinding(value, in: range, step: step), in: range)
                .tint(BrandPalette.interfaceAccent)
                .controlSize(.small)
        } else {
            Slider(value: value, in: range)
                .tint(BrandPalette.interfaceAccent)
                .controlSize(.small)
        }
    }

    private func snappedBinding(
        _ value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double
    ) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                let snappedValue = (newValue / step).rounded() * step
                value.wrappedValue = min(max(snappedValue, range.lowerBound), range.upperBound)
            }
        )
    }

    private func sliderValue(_ value: Binding<Double>) -> some View {
        Text("\(Int(value.wrappedValue * 100))%")
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .trailing)
    }
}
