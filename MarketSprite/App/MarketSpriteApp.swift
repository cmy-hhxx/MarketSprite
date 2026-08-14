import AppKit
import SwiftUI

@main
struct MarketSpriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bootstrap: AppBootstrap
    @StateObject private var preferences: AppPreferences

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _bootstrap = StateObject(
            wrappedValue: AppBootstrap(preferences: preferences)
        )
    }

    var body: some Scene {
        WindowGroup(AppIdentity.displayName, id: "market-sprite") {
            Group {
                if let store = bootstrap.store {
                    MarketMonitorView()
                        .environmentObject(store)
                        .background(
                            WindowConfigurator(
                                preferences: preferences,
                                clickThrough: preferences.clickThrough,
                                alwaysOnTop: preferences.alwaysOnTop
                            )
                        )
                        .task {
                            appDelegate.store = store
                        }
                } else if let failure = bootstrap.failure {
                    DatabaseUnavailableView(
                        failure: failure,
                        retry: { await bootstrap.retry() }
                    )
                } else {
                    ProgressView(tr("正在打开本地数据库…"))
                        .padding(36)
                }
            }
            .environmentObject(preferences)
            .task {
                appDelegate.preferences = preferences
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                    await bootstrap.start()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra(AppIdentity.displayName, image: "MenuBarIcon") {
            if let store = bootstrap.store {
                MenuBarContent()
                    .environmentObject(store)
                    .environmentObject(preferences)
            } else if let failure = bootstrap.failure {
                DatabaseUnavailableMenuContent(
                    failure: failure,
                    retry: { await bootstrap.retry() }
                )
            } else {
                Text(tr("正在打开本地数据库…"))
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            Group {
                if let store = bootstrap.store {
                    SettingsView()
                        .environmentObject(store)
                        .frame(
                            minWidth: SettingsWindowPresenter.minSize.width,
                            maxWidth: .infinity,
                            minHeight: SettingsWindowPresenter.minSize.height,
                            maxHeight: .infinity
                        )
                        .background(SettingsWindowChrome())
                } else if let failure = bootstrap.failure {
                    DatabaseUnavailableView(
                        failure: failure,
                        retry: { await bootstrap.retry() }
                    )
                } else {
                    ProgressView(tr("正在打开本地数据库…"))
                        .padding(36)
                }
            }
            .environmentObject(preferences)
        }
        .defaultSize(
            width: SettingsWindowPresenter.defaultSize.width,
            height: SettingsWindowPresenter.defaultSize.height
        )
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

private struct DatabaseUnavailableView: View {
    let failure: DatabaseStartupFailure
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(tr("本地数据库不可用"))
            } icon: {
                BrandIcon(systemName: "externaldrive.badge.exclamationmark")
            }
                .font(.title2.bold())
            Text(failure.message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !failure.databasePath.isEmpty {
                Text(failure.databasePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button(tr("重试")) {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)
                Button(tr("在 Finder 中显示目录")) {
                    revealDatabaseFolder()
                }
                Button(tr("退出"), role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(28)
        .frame(width: 520, alignment: .leading)
    }

    private func revealDatabaseFolder() {
        guard !failure.databasePath.isEmpty else { return }
        NSWorkspace.shared.open(
            URL(fileURLWithPath: failure.databasePath).deletingLastPathComponent()
        )
    }
}

private struct DatabaseUnavailableMenuContent: View {
    let failure: DatabaseStartupFailure
    let retry: () async -> Void

    var body: some View {
        Text(tr("本地数据库不可用"))
        Text(failure.message)
        Button(tr("重试")) {
            Task { await retry() }
        }
        Button(tr("在 Finder 中显示目录")) {
            guard !failure.databasePath.isEmpty else { return }
            NSWorkspace.shared.open(
                URL(fileURLWithPath: failure.databasePath).deletingLastPathComponent()
            )
        }
        Divider()
        Button(tr("退出 \(AppIdentity.displayName)")) {
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: MonitorStore? {
        didSet { updateGlobalShortcut() }
    }
    weak var preferences: AppPreferences? {
        didSet { updateGlobalShortcut() }
    }

    private let hotKeyController = GlobalHotKeyController()
    private var shortcutObserver: NSObjectProtocol?
    private var isTerminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.accessory)

        hotKeyController.onPress = { [weak self] in
            self?.toggleMonitorWindow()
        }
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .marketSpriteShortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateGlobalShortcut()
            }
        }
        updateGlobalShortcut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupApplicationResources()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminationPending else { return .terminateLater }
        guard let store else {
            cleanupApplicationResources()
            return .terminateNow
        }

        isTerminationPending = true
        Task { @MainActor [weak self] in
            await store.shutdown()
            self?.cleanupApplicationResources()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func cleanupApplicationResources() {
        hotKeyController.unregister()
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
            self.shortcutObserver = nil
        }
    }

    private func updateGlobalShortcut() {
        guard let preferences else { return }
        hotKeyController.register(
            enabled: preferences.shortcutEnabled,
            modifier: preferences.shortcutModifier,
            key: preferences.shortcutKey
        )
    }

    private func toggleMonitorWindow() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == WindowConfigurator.windowIdentifier
        }) else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(tr(monitorWindow?.isVisible == true ? "隐藏行情面板" : "显示行情面板")) {
            toggleMonitorWindow()
        }

        Button(tr("立即刷新")) {
            Task { await store.refreshAll() }
        }
        .keyboardShortcut("r")

        Toggle(tr("锁定并穿透鼠标"), isOn: $preferences.clickThrough)
        Toggle(tr("始终置顶"), isOn: $preferences.alwaysOnTop)

        Divider()

        Button(tr("设置…")) {
            SettingsWindowPresenter.open { openSettings() }
        }

        Divider()

        Button(tr("退出 \(AppIdentity.displayName)")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var monitorWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == WindowConfigurator.windowIdentifier }
    }

    private func toggleMonitorWindow() {
        guard let window = monitorWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}
