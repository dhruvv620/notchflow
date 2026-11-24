// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation

extension Defaults.Keys {
    /// Open the notch on the tab that fits the moment (meeting, timer, unread, music).
    /// Kept for older settings; `notchOpenTabMode` replaces it.
    static let notchContextAwareTab = Key<Bool>("notchContextAwareTab", default: true)
    /// Which tab the notch opens on (NotchOpenTabMode raw value; empty: from the older settings).
    static let notchOpenTabMode = Key<String>("notchOpenTabMode", default: "")
    /// The tab for "Always this tab" (a NotchBuiltinTab id).
    static let notchOpenFixedTab = Key<String>("notchOpenFixedTab", default: "music")
    /// Reasons Smart may not use (NotchContextTabPolicy.Tab raw values), e.g. "whatsapp".
    static let notchSmartTabSkips = Key<[String]>("notchSmartTabSkips", default: [])
    /// Something that needs you (an agent waiting, a promise due) opens its tab first.
    static let notchOpenUrgentFirst = Key<Bool>("notchOpenUrgentFirst", default: true)
}

/// Which tab the notch opens on.
enum NotchOpenTabMode: String, CaseIterable, Sendable {
    case music, fixed, last, smart

    var title: String {
        switch self {
        case .music: return String(localized: "Music")
        case .fixed: return String(localized: "Always this tab")
        case .last: return String(localized: "The last tab I used")
        case .smart: return String(localized: "Smart: the tab that fits the moment")
        }
    }
}

/// Applies the "Opens on" setting.
@MainActor
enum NotchOpenTab {
    static var mode: NotchOpenTabMode {
        if let mode = NotchOpenTabMode(rawValue: Defaults[.notchOpenTabMode]) { return mode }
        // Not chosen yet: what the older switches meant.
        if Defaults[.notchContextAwareTab] { return .smart }
        return DynamicIslandViewCoordinator.shared.openLastTabByDefault ? .last : .music
    }

    static func setMode(_ mode: NotchOpenTabMode) {
        Defaults[.notchOpenTabMode] = mode.rawValue
        Defaults[.notchContextAwareTab] = mode == .smart
        DynamicIslandViewCoordinator.shared.openLastTabByDefault = mode == .last
    }

    /// The tab for "Always this tab", if it's still shown.
    static var fixedView: NotchViews? {
        guard let tab = NotchBuiltinTab(rawValue: Defaults[.notchOpenFixedTab]) else { return nil }
        return TabSelectionView.availableTabs.contains(where: { $0.view == tab.view }) ? tab.view : nil
    }

    /// Where the notch goes back to when it closes (nil: stay on the current tab).
    static func viewAfterClose() -> NotchViews? {
        switch mode {
        case .last: return nil
        case .fixed: return fixedView ?? .home
        case .music, .smart: return .home
        }
    }

    /// The tab to switch to as the notch opens (nil: leave it).
    static func viewOnOpen() -> NotchViews? {
        switch mode {
        case .smart: return NotchContextTabResolver.preferredView()
        case .fixed: return fixedView
        case .music, .last: return nil
        }
    }
}

/// Maps the app's live state onto `NotchContextTabPolicy`.
@MainActor
enum NotchContextTabResolver {
    static func preferredView(now: Date = Date()) -> NotchViews? {
        guard NotchOpenTab.mode == .smart, !Defaults[.enableMinimalisticUI] else { return nil }

        var signals = NotchContextTabPolicy.Signals()
        if let event = NotchPeekSummaryBuilder.nextEvent(now: now) {
            signals.secondsUntilNextMeeting = event.start.timeIntervalSince(now)
        }
        signals.timerRunning = TimerManager.shared.isTimerActive
        signals.unreadWhatsApp = Defaults[.enableWhatsAppFeature] ? WhatsAppManager.shared.totalUnread : 0
        signals.unreadNotifications = Defaults[.communicationsEnabled] ? NotificationHub.shared.unseenCount : 0
        signals.musicPlaying = MusicManager.shared.isPlaying

        let visibleViews = Set(TabSelectionView.availableTabs.map(\.view))
        let skipped = Set(Defaults[.notchSmartTabSkips])
        let available = Set(NotchContextTabPolicy.Tab.allCases.filter {
            visibleViews.contains(view(for: $0)) && !skipped.contains($0.rawValue)
        })
        return NotchContextTabPolicy.choose(signals, available: available).map(view(for:))
    }

    private static func view(for tab: NotchContextTabPolicy.Tab) -> NotchViews {
        switch tab {
        case .calendar: return .calendar
        case .timer: return .timer
        case .whatsapp: return .whatsapp
        case .notifications: return .notifications
        case .music: return .home
        }
    }
}
