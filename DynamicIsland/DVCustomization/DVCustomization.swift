// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

enum DVCustomization {
    static let isEnabled = true

    static func configureDefaultsIfNeeded() {
        let preferences = UserDefaults.standard
        guard !preferences.bool(forKey: "dv.initialized.v1") else { return }
        Defaults[.showCalendar] = false
        Defaults[.showMirror] = false
        Defaults[.enableLyrics] = false
        Defaults[.enableMinimalisticUI] = false
        Defaults[.openNotchOnHover] = true
        Defaults[.musicControlWindowEnabled] = false
        Defaults[.enableSneakPeek] = false
        Defaults[.enableThirdPartyExtensions] = false
        Defaults[.enableStatsFeature] = false
        preferences.set(false, forKey: "firstLaunch")
        preferences.set(false, forKey: "showWhatsNew")
        preferences.set(true, forKey: "menubarIcon")
        preferences.set(true, forKey: "dv.initialized.v1")
    }
}

extension DynamicIslandViewModel {
    var dvPresentation: DVPresentation { dvInteraction.presentation }

    var dvNotchSize: CGSize {
        let hardware = getClosedNotchSize(screen: screen)
        let top = max(30, hardware.height)
        let maxWidth = maxAllowedNotchWidth(for: screen)
        switch dvPresentation {
        case .idle:
            return CGSize(width: min(maxWidth, max(250, hardware.width + 100)), height: top)
        case .preview:
            return CGSize(width: min(maxWidth, max(360, hardware.width + 150)), height: top + 80)
        case .expanded:
            return CGSize(width: min(maxWidth, max(480, hardware.width + 250)), height: top + 310)
        }
    }

}
