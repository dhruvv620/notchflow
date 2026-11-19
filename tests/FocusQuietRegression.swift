// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct FocusQuietRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "FocusQuietRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = FocusQuietPolicy

        // Quiet only during a running focus block, with the setting on.
        try require(P.isQuiet(enabled: true, isActive: true, isPaused: false, phaseIsFocus: true), "Running focus should be quiet")
        try require(!P.isQuiet(enabled: true, isActive: true, isPaused: true, phaseIsFocus: true), "A paused block should not hold")
        try require(!P.isQuiet(enabled: true, isActive: true, isPaused: false, phaseIsFocus: false), "Breaks should not hold")
        try require(!P.isQuiet(enabled: true, isActive: false, isPaused: false, phaseIsFocus: true), "No Pomodoro, no quiet")
        try require(!P.isQuiet(enabled: false, isActive: true, isPaused: false, phaseIsFocus: true), "Setting off, no quiet")

        // Calls follow their own switch; everything else is held.
        try require(P.holds(.call, allowCalls: false) && !P.holds(.call, allowCalls: true), "Calls switch ignored")
        try require(P.Kind.allCases.filter { $0 != .call }.allSatisfy { P.holds($0, allowCalls: true) }, "Other kinds must be held")

        // Summary wording and order.
        var held = P.Held()
        try require(P.summary(held) == nil, "Nothing held should give no summary")
        held.add(.notification); held.add(.notification); held.add(.notification); held.add(.message)
        try require(P.summary(held) == "While you focused: 3 notifications · 1 message", "Summary: \(P.summary(held) ?? "nil")")
        held.add(.agent)
        try require(P.summary(held) == "While you focused: 3 notifications · 1 message · 1 agent update", "Summary order: \(P.summary(held) ?? "nil")")
        try require(held.total == 5, "Total wrong")

        // Where a click on the summary goes.
        var messagesOnly = P.Held(); messagesOnly.add(.message); messagesOnly.add(.message)
        try require(P.destination(for: messagesOnly) == .whatsapp, "Messages only should open WhatsApp")
        var agentsOnly = P.Held(); agentsOnly.add(.agent)
        try require(P.destination(for: agentsOnly) == .agents, "Agent updates only should open AI Agents")
        try require(P.destination(for: held) == .notifications, "A mix should open Notifications")
        print("Focus quiet: OK")
    }
}
