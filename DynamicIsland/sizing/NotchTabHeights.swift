// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// How big the Cuely panel is (CuelyPanelSize raw value).
    static let cuelyPanelSize = Key<Int>("cuelyPanelSize", default: CuelyPanelSize.regular.rawValue)
}

extension NotchViews {
    /// How tall this tab wants the open notch. One table for the window, the
    /// visible panel and the view model, so the three can no longer disagree.
    var heightRule: NotchTabHeightRule {
        switch self {
        case .home:
            // Taller while the lyrics panel is open under the player.
            return .fitsContent(shrinkBy: 0, growBy: MusicLyricsPanel.height + 6)
        case .shelf, .llmUsage, .colorPicker, .clipboard, .cuely, .reminders, .calendar, .copyAction:
            return .preset
        // Stats and extension tabs keep their own row/preferred-height logic.
        case .stats, .extensionExperience:
            return .preset
        case .timer:
            // The ruler and presets need this much, even in Compact.
            return .atLeast(224)
        case .notes:
            return .fitsContent(shrinkBy: 0, growBy: 40)
        case .terminal:
            return .taller(by: 40)
        case .whatsapp:
            // A chat list beside a conversation and a reply field.
            return .taller(by: 60)
        case .agents:
            // Sessions beside a conversation and its message field.
            return .taller(by: 90)
        case .notifications:
            // A short inbox gets a short panel; a long one grows a little.
            return .fitsContent(shrinkBy: 40, growBy: 60)
        }
    }
}

/// The open notch size for a tab, from the user's panel size and what the tab
/// reported about its content. Main-actor isolated like the coordinator it reads;
/// every caller (the panel, the view model, the window sizing) runs there.
@MainActor
func tabOpenNotchSize(for view: NotchViews, preset: CGSize, screen: String?, closedHeight: CGFloat) -> CGSize {
    let coordinator = DynamicIslandViewCoordinator.shared
    let reported: CGFloat?
    if view == .notes {
        reported = coordinator.notesLayoutState.preferredHeight
    } else if view == .home {
        let lyricsOpen = Defaults[.musicLyricsExpanded] && Defaults[.enableLyrics] && !Defaults[.enableMinimalisticUI]
        reported = lyricsOpen ? preset.height + MusicLyricsPanel.height + 6 : nil
    } else if let content = coordinator.reportedContentHeights[view] {
        // Tabs report their content; the panel adds the notch header above it.
        let chrome = notchExpandedHeaderHeight(for: screen, closedHeight: closedHeight,
                                               minimalistic: Defaults[.enableMinimalisticUI]) + 8
        reported = content + chrome
    } else {
        reported = nil
    }
    let height = NotchTabHeightPolicy.height(preset: preset.height, rule: view.heightRule, reportedPanelHeight: reported)
    if view == .cuely, !Defaults[.enableMinimalisticUI] {
        // Cuely can be made bigger from its own size button.
        let size = CuelyPanelSize(rawValue: Defaults[.cuelyPanelSize]) ?? .regular
        return CGSize(width: max(preset.width, CGFloat(size.minimumWidth)), height: height + CGFloat(size.extraHeight))
    }
    return CGSize(width: preset.width, height: height)
}
