// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// How big the Cuely panel is (CuelyPanelSize raw value).
    static let cuelyPanelSize = Key<Int>("cuelyPanelSize", default: CuelyPanelSize.regular.rawValue)
    /// How big the AI Agents tab is (AgentPanelSize raw value).
    static let agentPanelSize = Key<Int>("agentPanelSize", default: AgentPanelSize.regular.rawValue)
}

/// Sizes for the AI Agents tab, from its size button: bigger panels show more
/// of a conversation, in larger text.
enum AgentPanelSize: Int, CaseIterable, Sendable {
    case regular = 0
    case large = 1
    case extraLarge = 2

    var title: String {
        switch self {
        case .regular: return "Regular"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }

    /// Added to the tab's usual height.
    var extraHeight: CGFloat {
        switch self {
        case .regular: return 0
        case .large: return 170
        case .extraLarge: return 340
        }
    }

    /// The panel is at least this wide (0: the usual width).
    var minimumWidth: CGFloat {
        switch self {
        case .regular: return 0
        case .large: return 820
        case .extraLarge: return 1000
        }
    }

    /// Chat text is scaled by this.
    var textScale: CGFloat {
        switch self {
        case .regular: return 1
        case .large: return 1.12
        case .extraLarge: return 1.25
        }
    }

    /// Width of the session list beside the conversation.
    var listWidth: CGFloat {
        switch self {
        case .regular: return 210
        case .large: return 240
        case .extraLarge: return 270
        }
    }

    var next: AgentPanelSize { AgentPanelSize(rawValue: (rawValue + 1) % Self.allCases.count) ?? .regular }
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
        // Stats keeps its own row-based height logic.
        case .stats:
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
        case .flow:
            // Workspace chips above today's time.
            return .taller(by: 50)
        case .notifications:
            // A short inbox gets a short panel; a long one grows a little.
            return .fitsContent(shrinkBy: 40, growBy: 60)
        }
    }
}

/// Makes a change that alters the open notch's size (a panel size button)
/// animate smoothly: the window makes room in the same frame, and the panel
/// animates into it.
@MainActor
func applyNotchLayoutChange(_ change: () -> Void) {
    withAnimation(.smooth(duration: NotchTabHeightPolicy.animationDuration)) {
        change()
        AppDelegate.shared?.refreshWindowForLayoutChange()
    }
}

/// The open notch size for a tab, from the user's panel size and what the tab
/// reported about its content. Main-actor isolated like the coordinator it reads;
/// every caller (the panel, the view model, the window sizing) runs there.
///
/// With `tallest`, the most the tab can need, whatever its content reports;
/// the window is kept that big while open so tab switches never resize it.
@MainActor
func tabOpenNotchSize(for view: NotchViews, preset: CGSize, screen: String?, closedHeight: CGFloat,
                      tallest: Bool = false) -> CGSize {
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
    let height = tallest
        ? NotchTabHeightPolicy.tallest(preset: preset.height, rule: view.heightRule)
        : NotchTabHeightPolicy.height(preset: preset.height, rule: view.heightRule, reportedPanelHeight: reported)
    if view == .cuely, !Defaults[.enableMinimalisticUI] {
        // Cuely can be made bigger from its own size button.
        let size = CuelyPanelSize(rawValue: Defaults[.cuelyPanelSize]) ?? .regular
        return CGSize(width: max(preset.width, CGFloat(size.minimumWidth)), height: height + CGFloat(size.extraHeight))
    }
    if view == .agents, !Defaults[.enableMinimalisticUI] {
        // So can AI Agents, for reading long conversations.
        let size = AgentPanelSize(rawValue: Defaults[.agentPanelSize]) ?? .regular
        return CGSize(width: max(preset.width, size.minimumWidth), height: height + size.extraHeight)
    }
    return CGSize(width: preset.width, height: height)
}
