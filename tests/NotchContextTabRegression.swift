// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct NotchContextTabRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotchContextTabRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = NotchContextTabPolicy
        let all = Set(P.Tab.allCases)
        var s = P.Signals()
        try require(P.choose(s, available: all) == nil, "Quiet moment changed the tab")
        s.musicPlaying = true
        try require(P.choose(s, available: all) == .music, "Playing music did not open Music")
        s.unreadNotifications = 2
        try require(P.choose(s, available: all) == .notifications, "Unread notifications did not beat music")
        s.unreadWhatsApp = 1
        try require(P.choose(s, available: all) == .whatsapp, "Unread WhatsApp did not beat notifications")
        s.timerRunning = true
        try require(P.choose(s, available: all) == .timer, "A running timer did not beat messages")
        s.secondsUntilNextMeeting = 240
        try require(P.choose(s, available: all) == .calendar, "A meeting in 4 minutes did not open Calendar")
        s.secondsUntilNextMeeting = -600
        try require(P.choose(s, available: all) == .calendar, "An ongoing meeting did not open Calendar")
        s.secondsUntilNextMeeting = 1200
        try require(P.choose(s, available: all) == .timer, "A meeting 20 minutes away took over")
        try require(P.choose(s, available: [.music, .notifications]) == .notifications, "A hidden tab was chosen")
        try require(P.choose(s, available: []) == nil, "A tab was chosen with none visible")
        print("Context tab checks passed")
    }
}
