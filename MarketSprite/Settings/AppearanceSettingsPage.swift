import SwiftUI

struct AppearanceSettingsPage: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var loginItem: LoginItemController

    var body: some View {
        Form {
            Section("显示效果") {
                LabeledContent {
                    sliderControl(
                        value: $preferences.displayScale,
                        range: 0.65...1.6,
                        step: 0.05,
                        suffix: "%"
                    )
                } label: {
                    Label("整体大小", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                LabeledContent {
                    sliderControl(
                        value: $preferences.lineOpacity,
                        range: 0.15...1,
                        suffix: "%"
                    )
                } label: {
                    Label("曲线不透明度", systemImage: "waveform.path.ecg")
                }

                LabeledContent {
                    sliderControl(
                        value: $preferences.labelOpacity,
                        range: 0.72...1,
                        suffix: "%"
                    )
                } label: {
                    Label("名称与数字不透明度", systemImage: "textformat")
                }

                LabeledContent {
                    sliderControl(
                        value: $preferences.backgroundOpacity,
                        range: 0...1,
                        suffix: "%"
                    )
                } label: {
                    Label("背景板不透明度", systemImage: "square.on.square")
                }

                LabeledContent {
                    Button("恢复默认") {
                        preferences.resetAppearance()
                    }
                    .buttonStyle(.borderless)
                } label: {
                    Label("默认外观", systemImage: "arrow.counterclockwise")
                }
            }

            Section("窗口行为") {
                Toggle(isOn: $preferences.compactMode) {
                    Label("紧凑模式", systemImage: "rectangle.compress.vertical")
                }

                Toggle(isOn: $preferences.alwaysOnTop) {
                    Label("始终置顶", systemImage: "pin.fill")
                }

                Toggle(
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )
                ) {
                    Label("登录时自动启动", systemImage: "power")
                }
                .disabled(loginItem.isUpdating)

                if let message = loginItem.message {
                    HStack(alignment: .top, spacing: 12) {
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

                Toggle(isOn: $preferences.clickThrough) {
                    Label("鼠标穿透（从菜单栏恢复）", systemImage: "cursorarrow.slash")
                }
                .help(tr("开启后，请从菜单栏图标关闭鼠标穿透。"))
            }

            Section("快捷键") {
                Toggle(isOn: $preferences.shortcutEnabled) {
                    Label("显示/隐藏行情面板", systemImage: "keyboard")
                }

                LabeledContent {
                    HStack(spacing: 8) {
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
                } label: {
                    Text("按键组合")
                }
                .disabled(!preferences.shortcutEnabled)
                .opacity(preferences.shortcutEnabled ? 1 : 0.45)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func sliderControl(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        suffix: String
    ) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: range, step: step ?? 0.01)
                .tint(.accentColor)
                .controlSize(.small)

            Text("\(Int(value.wrappedValue * 100))\(suffix)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(minWidth: 180, idealWidth: 280, maxWidth: 360)
    }
}
