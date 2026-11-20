// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

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
        // The third-party extension system (removed with its SDK).
        "enableThirdPartyExtensions", "enableExtensionLiveActivities", "enableExtensionLockScreenWidgets",
        "enableExtensionNotchExperiences", "enableExtensionNotchTabs", "enableExtensionNotchMinimalisticOverrides",
        "enableExtensionNotchInteractiveWebViews", "extensionAuthorizationEntries", "extensionRateLimitRecords",
        "extensionDiagnosticsLoggingEnabled", "extensionLiveActivityCapacity", "extensionLockScreenWidgetCapacity",
        "extensionNotchExperienceCapacity", "enableExtensionFileSharing",
        // The clipboard button in the notch header (replaced by the Focus button).
        "showClipboardIcon",
        // Time tracking was on by default; it is now off until turned on again.
        "enableTimeTracking",
        // The Optimizer's "Shrink the window when the notch closes": growing the
        // window again on every opening made the notch open off-center.
        "optimizeShrinkWindow",
    ]

    private static let doneKey = "settingsCleanup.v5"

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        removedKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.set(true, forKey: doneKey)
    }
}
