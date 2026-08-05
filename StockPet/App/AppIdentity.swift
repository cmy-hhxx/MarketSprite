import Foundation

enum AppIdentity {
    static let displayName = "MarketSprite"
    static let bundleIdentifier = "io.github.cmy-hhxx.marketsprite"
    static let applicationSupportFolderName = "MarketSprite"

    static let legacyBundleIdentifier = "com.mingyhud.app"
    static let legacyApplicationSupportFolderName = "MingyHUD"
}

enum AppDataMigrator {
    static let preferencesMigrationMarkerKey = "marketSprite.migratedPreferencesFromMingyHUD"
    private static let legacyPreferencePrefix = "stockPet."

    static func migrateLegacyUserData(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let legacyDomain = defaults.persistentDomain(
            forName: AppIdentity.legacyBundleIdentifier
        )
        migratePreferences(legacyDomain: legacyDomain, to: defaults)

        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        do {
            try migrateApplicationSupport(in: applicationSupport, fileManager: fileManager)
        } catch {
            NSLog("MarketSprite data migration failed: %@", error.localizedDescription)
        }
    }

    static func migratePreferences(
        legacyDomain: [String: Any]?,
        to defaults: UserDefaults
    ) {
        guard !defaults.bool(forKey: preferencesMigrationMarkerKey) else { return }

        if let legacyDomain {
            for (key, value) in legacyDomain
            where key.hasPrefix(legacyPreferencePrefix) && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: preferencesMigrationMarkerKey)
    }

    static func migrateApplicationSupport(
        in applicationSupport: URL,
        fileManager: FileManager
    ) throws {
        let legacyFolder = applicationSupport.appendingPathComponent(
            AppIdentity.legacyApplicationSupportFolderName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: legacyFolder.path) else { return }

        let currentFolder = applicationSupport.appendingPathComponent(
            AppIdentity.applicationSupportFolderName,
            isDirectory: true
        )
        if !fileManager.fileExists(atPath: currentFolder.path) {
            try fileManager.copyItem(at: legacyFolder, to: currentFolder)
            return
        }

        for legacyItem in try fileManager.contentsOfDirectory(
            at: legacyFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            let currentItem = currentFolder.appendingPathComponent(legacyItem.lastPathComponent)
            guard !fileManager.fileExists(atPath: currentItem.path) else { continue }
            try fileManager.copyItem(at: legacyItem, to: currentItem)
        }
    }
}
