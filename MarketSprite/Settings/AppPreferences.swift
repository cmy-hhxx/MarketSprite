import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    @Published var lineOpacity: Double {
        didSet { persist(lineOpacity, key: Keys.lineOpacity) }
    }
    @Published var labelOpacity: Double {
        didSet { persist(labelOpacity, key: Keys.labelOpacity) }
    }
    @Published var backgroundOpacity: Double {
        didSet { persist(backgroundOpacity, key: Keys.backgroundOpacity) }
    }
    @Published var refreshInterval: Int {
        didSet { persist(refreshInterval, key: Keys.refreshInterval) }
    }
    @Published var clickThrough: Bool {
        didSet { persist(clickThrough, key: Keys.clickThrough) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { persist(alwaysOnTop, key: Keys.alwaysOnTop) }
    }
    @Published var compactMode: Bool {
        didSet { persist(compactMode, key: Keys.compactMode) }
    }
    @Published var displayScale: Double {
        didSet { persist(displayScale, key: Keys.displayScale) }
    }
    @Published var bullSoundEnabled: Bool {
        didSet { persist(bullSoundEnabled, key: Keys.bullSoundEnabled) }
    }
    @Published var bearSoundEnabled: Bool {
        didSet { persist(bearSoundEnabled, key: Keys.bearSoundEnabled) }
    }
    @Published var alertOpacity: Double {
        didSet { persist(alertOpacity, key: Keys.alertOpacity) }
    }
    @Published var shortcutEnabled: Bool {
        didSet {
            persist(shortcutEnabled, key: Keys.shortcutEnabled)
            notifyShortcutChanged()
        }
    }
    @Published var shortcutModifier: ShortcutModifierOption {
        didSet {
            persist(shortcutModifier.rawValue, key: Keys.shortcutModifier)
            notifyShortcutChanged()
        }
    }
    @Published var shortcutKey: ShortcutKeyOption {
        didSet {
            persist(shortcutKey.rawValue, key: Keys.shortcutKey)
            notifyShortcutChanged()
        }
    }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lineOpacity = Self.clamp(
            Self.double(defaults, key: Keys.lineOpacity, fallback: 0.92),
            to: 0.15...1
        )
        labelOpacity = Self.clamp(
            Self.double(defaults, key: Keys.labelOpacity, fallback: 0.92),
            to: 0.72...1
        )
        backgroundOpacity = Self.clamp(
            Self.double(defaults, key: Keys.backgroundOpacity, fallback: 0.55),
            to: 0...1
        )
        refreshInterval = Self.sanitizedRefreshInterval(
            Self.integer(defaults, key: Keys.refreshInterval, fallback: 15)
        )
        clickThrough = Self.bool(defaults, key: Keys.clickThrough, fallback: false)
        alwaysOnTop = Self.bool(defaults, key: Keys.alwaysOnTop, fallback: true)
        compactMode = Self.bool(defaults, key: Keys.compactMode, fallback: false)
        displayScale = Self.clamp(
            Self.double(defaults, key: Keys.displayScale, fallback: 1),
            to: 0.65...1.6
        )
        bullSoundEnabled = Self.bool(
            defaults,
            key: Keys.bullSoundEnabled,
            fallback: true
        )
        bearSoundEnabled = Self.bool(
            defaults,
            key: Keys.bearSoundEnabled,
            fallback: true
        )
        alertOpacity = Self.clamp(
            Self.double(defaults, key: Keys.alertOpacity, fallback: 0.94),
            to: 0.2...1
        )
        shortcutEnabled = Self.bool(
            defaults,
            key: Keys.shortcutEnabled,
            fallback: true
        )
        shortcutModifier = ShortcutModifierOption(
            rawValue: defaults.string(forKey: Keys.shortcutModifier) ?? ""
        ) ?? .commandOption
        shortcutKey = ShortcutKeyOption(
            rawValue: defaults.string(forKey: Keys.shortcutKey) ?? ""
        ) ?? .s
        isLoading = false
    }

    func resetAppearance() {
        lineOpacity = 0.92
        labelOpacity = 0.92
        backgroundOpacity = 0.55
        compactMode = false
        displayScale = 1
    }

    var monitorWindowOrigin: CGPoint? {
        guard let values = defaults.array(forKey: Keys.monitorWindowOrigin),
              values.count == 2,
              let x = (values[0] as? NSNumber)?.doubleValue,
              let y = (values[1] as? NSNumber)?.doubleValue,
              x.isFinite,
              y.isFinite
        else { return nil }
        return CGPoint(x: x, y: y)
    }

    func saveMonitorWindowOrigin(_ origin: CGPoint) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        persist(
            [Double(origin.x), Double(origin.y)],
            key: Keys.monitorWindowOrigin
        )
    }

    private func persist(_ value: Any, key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private func notifyShortcutChanged() {
        guard !isLoading else { return }
        NotificationCenter.default.post(name: .marketSpriteShortcutChanged, object: nil)
    }

    private static func double(
        _ defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    private static func integer(
        _ defaults: UserDefaults,
        key: String,
        fallback: Int
    ) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private static func bool(
        _ defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func sanitizedRefreshInterval(_ value: Int) -> Int {
        [15, 30, 60].contains(value) ? value : 15
    }

    private enum Keys {
        static let lineOpacity = "marketSprite.lineOpacity"
        static let labelOpacity = "marketSprite.labelOpacity"
        static let backgroundOpacity = "marketSprite.backgroundOpacity"
        static let refreshInterval = "marketSprite.refreshInterval"
        static let clickThrough = "marketSprite.clickThrough"
        static let alwaysOnTop = "marketSprite.alwaysOnTop"
        static let compactMode = "marketSprite.compactMode"
        static let displayScale = "marketSprite.displayScale"
        static let bullSoundEnabled = "marketSprite.bullSoundEnabled"
        static let bearSoundEnabled = "marketSprite.bearSoundEnabled"
        static let alertOpacity = "marketSprite.alertOpacity"
        static let shortcutEnabled = "marketSprite.shortcutEnabled"
        static let shortcutModifier = "marketSprite.shortcutModifier"
        static let shortcutKey = "marketSprite.shortcutKey"
        static let monitorWindowOrigin = "marketSprite.monitorWindowOrigin"
    }
}
