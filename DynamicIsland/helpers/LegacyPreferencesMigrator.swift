// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Preserves settings from the earlier Debug-only bundle identifier when local
/// Debug and Release builds move to one stable application identity.
enum LegacyPreferencesMigrator {
    private static let legacyBundleIdentifier = "com.dhruvv620.NotchFlowFresh.dev"
    private static let migrationKey = "notchFlowDidMigrateLegacyDebugPreferences"
    private static let reminderOptInMigrationKey = "notchFlowDidMakeRemindersOptIn"

    static func migrateIfNeeded() {
        guard Bundle.main.bundleIdentifier == "com.dhruvv620.NotchFlowFresh" else { return }
        let defaults = UserDefaults.standard
        let current = defaults.persistentDomain(forName: "com.dhruvv620.NotchFlowFresh") ?? [:]
        if current[migrationKey] == nil {
            if let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier) {
                for (key, value) in legacy where current[key] == nil {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: migrationKey)
        }

        // Older builds enabled both the Todos module and reminder live activity
        // by default. Turn them off once so reminders cannot appear in the notch
        // until the user explicitly enables either feature again.
        if current[reminderOptInMigrationKey] == nil {
            defaults.set(false, forKey: "enableRemindersFeature")
            defaults.set(false, forKey: "enableReminderLiveActivity")
            defaults.set(true, forKey: reminderOptInMigrationKey)
        }
    }
}
