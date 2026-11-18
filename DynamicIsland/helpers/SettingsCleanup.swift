// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Settings that were removed because nothing used them any more, or because
/// a newer feature replaced them. Their stored values are cleared once so the
/// preferences file only holds settings the app still reads.
enum SettingsCleanup {
    static let removedKeys = [
        "releaseName", "showEmojis", "lightingEffect", "customVisualizers", "enableSafariDownloads",
        "selectedDownloadIconStyle", "expandedDragDetection", "alwaysHideInFullscreen", "enableWobbleAnimation",
        "autoStartStatsMonitoring", "showTimerPresetsInNotchTab", "timerInputStyle", "colorHistorySize",
        "clipboardHistorySize", "systemHUDSensitivity", "hasSeenOSDAlphaWarning", "enableScreenRecordingPolling",
    ]

    private static let doneKey = "settingsCleanup.v1"

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        removedKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.set(true, forKey: doneKey)
    }
}
