import SwiftUI

struct AppearanceSettingsPage: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageTitle(
                title: "外观与交互",
                subtitle: "让它融进桌面，而不是挡住工作"
            )

            SettingsCard {
                HStack {
                    Label("整体大小", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 130, alignment: .leading)
                    Slider(value: $preferences.displayScale, in: 0.65...1.6, step: 0.05)
                    Text("\(Int(preferences.displayScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Divider().opacity(0.5)
                opacitySlider(
                    title: "曲线不透明度",
                    icon: "waveform.path.ecg",
                    value: $preferences.lineOpacity,
                    range: 0.15...1
                )
                Divider().opacity(0.5)
                opacitySlider(
                    title: "名称与数字不透明度",
                    icon: "textformat",
                    value: $preferences.labelOpacity,
                    range: 0.35...1
                )
                Divider().opacity(0.5)
                opacitySlider(
                    title: "背景板不透明度",
                    icon: "square.on.square",
                    value: $preferences.backgroundOpacity,
                    range: 0...0.55
                )
            }

            SettingsCard {
                Toggle(isOn: $preferences.compactMode) {
                    Label("紧凑模式", systemImage: "rectangle.compress.vertical")
                }
                Divider().opacity(0.5)
                Toggle(isOn: $preferences.alwaysOnTop) {
                    Label("始终置顶", systemImage: "pin.fill")
                }
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $preferences.clickThrough) {
                        Label("锁定并穿透鼠标", systemImage: "cursorarrow.slash")
                    }
                    Text("锁定后需从菜单栏的曲线图标关闭穿透。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }

            SettingsCard {
                Toggle(isOn: $preferences.shortcutEnabled) {
                    Label("快捷键显示/隐藏行情面板", systemImage: "keyboard")
                }
                Divider().opacity(0.5)
                HStack {
                    Text("快捷键组合")
                    Spacer()
                    Picker("", selection: $preferences.shortcutModifier) {
                        ForEach(ShortcutModifierOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 86)

                    Text("+")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $preferences.shortcutKey) {
                        ForEach(ShortcutKeyOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 78)
                }
                .disabled(!preferences.shortcutEnabled)
                .opacity(preferences.shortcutEnabled ? 1 : 0.45)
            }

            Button("恢复默认外观") {
                preferences.resetAppearance()
            }
            .buttonStyle(.bordered)
        }
    }

    private func opacitySlider(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Label(tr(title), systemImage: icon)
                .frame(width: 160, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
