// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import Foundation

extension Defaults.Keys {
    /// Open the notch on the tab that fits the moment (meeting, timer, unread, music).
    static let notchContextAwareTab = Key<Bool>("notchContextAwareTab", default: true)
}

/// Maps the app's live state onto `NotchContextTabPolicy`.
@MainActor
enum NotchContextTabResolver {
    static func preferredView(now: Date = Date()) -> NotchViews? {
        guard Defaults[.notchContextAwareTab], !Defaults[.enableMinimalisticUI] else { return nil }

        var signals = NotchContextTabPolicy.Signals()
        if let event = NotchPeekSummaryBuilder.nextEvent(now: now) {
            signals.secondsUntilNextMeeting = event.start.timeIntervalSince(now)
        }
        signals.timerRunning = TimerManager.shared.isTimerActive
        signals.unreadWhatsApp = Defaults[.enableWhatsAppFeature] ? WhatsAppManager.shared.totalUnread : 0
        signals.unreadNotifications = Defaults[.communicationsEnabled] ? NotificationHub.shared.unseenCount : 0
        signals.musicPlaying = MusicManager.shared.isPlaying

        let visibleViews = Set(TabSelectionView.availableTabs.map(\.view))
        let available = Set(NotchContextTabPolicy.Tab.allCases.filter { visibleViews.contains(view(for: $0)) })
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
