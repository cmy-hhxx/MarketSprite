import XCTest
@testable import MarketSprite

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testPreferencesUseOnlyMarketSpriteKeysAndRoundTrip() {
        let suiteName = "MarketSpriteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.lineOpacity = 0.8
        preferences.labelOpacity = 0.7
        preferences.backgroundOpacity = 0.2
        preferences.refreshInterval = 30
        preferences.clickThrough = true
        preferences.alwaysOnTop = false
        preferences.compactMode = true
        preferences.displayScale = 1.2
        preferences.bullSoundEnabled = false
        preferences.bearSoundEnabled = false
        preferences.alertOpacity = 0.75
        preferences.shortcutEnabled = false
        preferences.shortcutModifier = .controlShift
        preferences.shortcutKey = .space
        let windowOrigin = CGPoint(x: 320, y: 180)
        preferences.saveMonitorWindowOrigin(windowOrigin)

        let storedKeys = Set(
            defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? []
        )
        XCTAssertFalse(storedKeys.isEmpty)
        XCTAssertTrue(storedKeys.allSatisfy { $0.hasPrefix("marketSprite.") })

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.lineOpacity, 0.8)
        XCTAssertEqual(reloaded.labelOpacity, 0.7)
        XCTAssertEqual(reloaded.backgroundOpacity, 0.2)
        XCTAssertEqual(reloaded.refreshInterval, 30)
        XCTAssertTrue(reloaded.clickThrough)
        XCTAssertFalse(reloaded.alwaysOnTop)
        XCTAssertTrue(reloaded.compactMode)
        XCTAssertEqual(reloaded.displayScale, 1.2)
        XCTAssertFalse(reloaded.bullSoundEnabled)
        XCTAssertFalse(reloaded.bearSoundEnabled)
        XCTAssertEqual(reloaded.alertOpacity, 0.75)
        XCTAssertFalse(reloaded.shortcutEnabled)
        XCTAssertEqual(reloaded.shortcutModifier, .controlShift)
        XCTAssertEqual(reloaded.shortcutKey, .space)
        XCTAssertEqual(reloaded.monitorWindowOrigin, windowOrigin)
    }

    func testInvalidStoredAppearanceAndRefreshValuesAreSanitizedOnLoad() {
        let suiteName = "MarketSpriteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(-2.0, forKey: "marketSprite.lineOpacity")
        defaults.set(3.0, forKey: "marketSprite.labelOpacity")
        defaults.set(4.0, forKey: "marketSprite.backgroundOpacity")
        defaults.set(1, forKey: "marketSprite.refreshInterval")
        defaults.set(8.0, forKey: "marketSprite.displayScale")
        defaults.set(-1.0, forKey: "marketSprite.alertOpacity")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.lineOpacity, 0.15)
        XCTAssertEqual(preferences.labelOpacity, 1)
        XCTAssertEqual(preferences.backgroundOpacity, 0.55)
        XCTAssertEqual(preferences.refreshInterval, 15)
        XCTAssertEqual(preferences.displayScale, 1.6)
        XCTAssertEqual(preferences.alertOpacity, 0.2)
    }
}
