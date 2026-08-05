import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    static let windowIdentifier = "stock-pet-floating-window"

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

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.styleMask = .borderless
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = clickThrough
        window.setFrameAutosaveName("StockPetFloatingFrame")
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        coordinator.install(on: window)
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var monitor: Any?

        func install(on window: NSWindow) {
            guard self.window !== window || monitor == nil else { return }
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            self.window = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if event.window === self?.window, event.clickCount == 2 {
                    NotificationCenter.default.post(name: .stockPetOpenSettings, object: nil)
                }
                return event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

extension Notification.Name {
    static let stockPetOpenSettings = Notification.Name("stockPet.openSettings")
}

@MainActor
enum SettingsWindowPresenter {
    static let windowIdentifier = "mingyhud-settings-window"
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
        let petID = WindowConfigurator.windowIdentifier
        let candidates = NSApp.windows.filter { window in
            window.identifier?.rawValue != petID
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
    private var mouseUpMonitor: Any?

    func attach(_ window: NSWindow) {
        if self.window !== window {
            self.window = window
            styleObservation?.invalidate()
            styleObservation = window.observe(\.styleMask, options: [.new]) { [weak self] win, _ in
                Task { @MainActor in
                    self?.ensureResizable(win)
                }
            }
            installMouseUpMonitorIfNeeded()
            applyChrome(window)
        } else {
            ensureResizable(window)
            enforceSizeLimits(window)
        }
    }

    private func installMouseUpMonitorIfNeeded() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in
                guard let self, let window = self.window else { return }
                self.applyChrome(window)
            }
            return event
        }
    }

    private func applyChrome(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowPresenter.windowIdentifier)
        ensureResizable(window)
        enforceSizeLimits(window)
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
    }

    private func ensureResizable(_ window: NSWindow) {
        guard !window.styleMask.contains(.resizable) else { return }
        // Avoid touching styleMask while the user is actively dragging.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
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
