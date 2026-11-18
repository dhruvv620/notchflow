// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Picks the tab that fits the moment when the notch opens.
///
/// Pure decision logic (no UI, settings or managers), so Build.command can
/// check it alone. The app maps its state into `Signals` and the result back
/// onto its tabs.
enum NotchContextTabPolicy {
    enum Tab: String, CaseIterable, Sendable {
        case calendar, timer, whatsapp, notifications, music
    }

    struct Signals: Equatable, Sendable {
        /// Seconds until the next timed event starts; negative while it runs.
        var secondsUntilNextMeeting: TimeInterval?
        var timerRunning = false
        var unreadWhatsApp = 0
        var unreadNotifications = 0
        var musicPlaying = false
    }

    /// How early before a meeting the notch opens on the calendar.
    static let meetingLeadTime: TimeInterval = 5 * 60

    /// The tab to open on, among those the user can see, or nil to keep the
    /// usual behaviour. Order: an imminent meeting, a running timer, unread
    /// messages, then whatever is playing.
    static func choose(_ signals: Signals, available: Set<Tab>) -> Tab? {
        var ranked: [Tab] = []
        if let seconds = signals.secondsUntilNextMeeting, seconds <= meetingLeadTime {
            ranked.append(.calendar)
        }
        if signals.timerRunning { ranked.append(.timer) }
        if signals.unreadWhatsApp > 0 { ranked.append(.whatsapp) }
        if signals.unreadNotifications > 0 { ranked.append(.notifications) }
        if signals.musicPlaying { ranked.append(.music) }
        return ranked.first { available.contains($0) }
    }
}
