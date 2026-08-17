import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    static let windowIdentifier = "market-sprite-floating-window"

    let preferences: AppPreferences
    let clickThrough: Bool
    let alwaysOnTop: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.styleMask = .borderless
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = clickThrough
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        coordinator.install(on: window, preferences: preferences)
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private weak var preferences: AppPreferences?
        private var monitor: Any?
        private var moveObserver: NSObjectProtocol?

        func install(on window: NSWindow, preferences: AppPreferences) {
            self.preferences = preferences
            guard self.window !== window || monitor == nil else { return }
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            if let moveObserver {
                NotificationCenter.default.removeObserver(moveObserver)
            }
            self.window = window
            restoreOrigin(of: window, from: preferences)
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor in
                    guard let self, let window else { return }
                    self.preferences?.saveMonitorWindowOrigin(window.frame.origin)
                }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if event.window === self?.window, event.clickCount == 2 {
                    NotificationCenter.default.post(name: .marketSpriteOpenSettings, object: nil)
                }
                return event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            if let moveObserver {
                NotificationCenter.default.removeObserver(moveObserver)
                self.moveObserver = nil
            }
            window = nil
            preferences = nil
        }

        private func restoreOrigin(of window: NSWindow, from preferences: AppPreferences) {
            guard let origin = preferences.monitorWindowOrigin else { return }
            var proposedFrame = window.frame
            proposedFrame.origin = origin
            guard NSScreen.screens.contains(where: {
                $0.visibleFrame.intersects(proposedFrame)
            }) else { return }
            window.setFrameOrigin(origin)
        }

    }
}

extension Notification.Name {
    static let marketSpriteOpenSettings = Notification.Name("marketSprite.openSettings")
}

@MainActor
enum SettingsWindowPresenter {
    static let windowIdentifier = "market-sprite-settings-window"
    static let defaultSize = NSSize(width: 780, height: 660)
    static let minSize = NSSize(width: 680, height: 520)

    static func open(_ openSettings: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            present(center: true)
        }
    }

    static func present(center: Bool) {
        guard let window = findSettingsWindow() else { return }
        let wasHidden = !window.isVisible
        SettingsWindowKeeper.shared.attach(window)
        if center && wasHidden {
            window.setContentSize(defaultSize)
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    static func findSettingsWindow() -> NSWindow? {
        let monitorWindowID = WindowConfigurator.windowIdentifier
        let candidates = NSApp.windows.filter { window in
            window.identifier?.rawValue != monitorWindowID
                && window.canBecomeKey
                && window.styleMask.contains(.titled)
        }
        if let tagged = candidates.first(where: { $0.identifier?.rawValue == windowIdentifier }) {
            return tagged
        }
        return candidates.first {
            $0.title.contains("设置") || $0.title.localizedCaseInsensitiveContains("settings")
        } ?? candidates.last
    }
}

/// Keeps Settings window resizable without re-applying chrome during live resize.
@MainActor
final class SettingsWindowKeeper {
    static let shared = SettingsWindowKeeper()

    private weak var window: NSWindow?
    private var styleObservation: NSKeyValueObservation?
    private var resizeObserver: NSObjectProtocol?
    private var trafficLightBaselineFrames: [NSRect] = []
    private var hasInstalledTrafficLightLayout = false

    func attach(_ window: NSWindow) {
        if self.window !== window {
            self.window = window
            styleObservation?.invalidate()
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            trafficLightBaselineFrames = []
            hasInstalledTrafficLightLayout = false
            styleObservation = window.observe(\.styleMask, options: [.new]) { [weak self] win, _ in
                Task { @MainActor in
                    self?.ensureResizable(win)
                }
            }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor in
                    guard let self, let window else { return }
                    self.positionTrafficLightButtons(in: window)
                }
            }
            applyChrome(window)
        } else {
            ensureResizable(window)
            enforceSizeLimits(window)
            positionTrafficLightButtons(in: window)
        }
    }

    private func applyChrome(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowPresenter.windowIdentifier)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = SettingsVisualStyle.windowBackgroundColor
        window.isMovableByWindowBackground = true
        ensureResizable(window)
        enforceSizeLimits(window)
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.positionTrafficLightButtons(in: window)
        }
    }

    private func positionTrafficLightButtons(in window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ]
        let buttons = buttonTypes.compactMap(window.standardWindowButton)
        guard
            buttons.count == buttonTypes.count,
            let titlebarView = buttons.first?.superview
        else { return }

        titlebarView.layoutSubtreeIfNeeded()
        if trafficLightBaselineFrames.count != buttons.count {
            trafficLightBaselineFrames = buttons.map(\.frame)
        }
        guard trafficLightBaselineFrames.count == buttons.count else { return }

        if !hasInstalledTrafficLightLayout {
            deactivateTrafficLightPositioningConstraints(for: buttons, in: titlebarView)
            buttons.forEach { $0.translatesAutoresizingMaskIntoConstraints = true }
            hasInstalledTrafficLightLayout = true
        }

        let spacing = trafficLightBaselineFrames[1].minX - trafficLightBaselineFrames[0].minX
        for (index, button) in buttons.enumerated() {
            let baseline = trafficLightBaselineFrames[index]
            button.setFrameOrigin(
                NSPoint(
                    x: SettingsVisualStyle.trafficLightLeadingInset + spacing * CGFloat(index),
                    y: baseline.minY
                )
            )
        }
    }

    private func deactivateTrafficLightPositioningConstraints(
        for buttons: [NSButton],
        in titlebarView: NSView
    ) {
        let buttonIdentifiers = Set(buttons.map(ObjectIdentifier.init))
        var currentView: NSView? = titlebarView

        while let view = currentView {
            for constraint in view.constraints {
                let firstItem = (constraint.firstItem as? NSView).map(ObjectIdentifier.init)
                let secondItem = (constraint.secondItem as? NSView).map(ObjectIdentifier.init)
                if firstItem.map(buttonIdentifiers.contains) ?? false
                    || secondItem.map(buttonIdentifiers.contains) ?? false {
                    constraint.isActive = false
                }
            }
            currentView = view.superview
        }
    }

    private func ensureResizable(_ window: NSWindow) {
        let requiredStyle: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView,
        ]
        guard !window.styleMask.contains(requiredStyle) else { return }
        // Avoid touching styleMask while the user is actively dragging.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        window.styleMask.insert(requiredStyle)
    }

    private func enforceSizeLimits(_ window: NSWindow) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let minSize = SettingsWindowPresenter.minSize
        if window.minSize != minSize {
            window.minSize = minSize
        }
        let unlimited = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if window.maxSize.width < 10_000 || window.maxSize.height < 10_000 {
            window.maxSize = unlimited
        }
    }
}

/// Attaches Settings window chrome once; never rewrites styleMask on every SwiftUI refresh.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                SettingsWindowKeeper.shared.attach(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only attach when the view first gains a window; do not reconfigure every update
        // (rewriting styleMask mid-drag cancels resize).
        guard let window = nsView.window else { return }
        if window.identifier?.rawValue != SettingsWindowPresenter.windowIdentifier {
            SettingsWindowKeeper.shared.attach(window)
        }
    }
}
