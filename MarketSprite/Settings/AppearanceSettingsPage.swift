import SwiftUI

struct AppearanceSettingsPage: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
                        range: 0.35...1
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
                        .buttonStyle(.bordered)
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
            HStack(spacing: 16) {
                Label(title, systemImage: icon)
                Spacer(minLength: 20)
                sliderControl(value: value, range: range, step: step)
                    .frame(width: 260)
                sliderValue(value)
            }

            HStack(spacing: 12) {
                Label(title, systemImage: icon)
                Spacer(minLength: 8)
                sliderControl(value: value, range: range, step: step)
                    .frame(minWidth: 92, idealWidth: 132, maxWidth: 156)
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
            Slider(value: value, in: range, step: step)
        } else {
            Slider(value: value, in: range)
        }
    }

    private func sliderValue(_ value: Binding<Double>) -> some View {
        Text("\(Int(value.wrappedValue * 100))%")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
    }
}
