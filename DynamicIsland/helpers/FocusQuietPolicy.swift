// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// What stays quiet during a Pomodoro focus block, and the line shown after
/// it. Foundation only, so Build.command can check it alone.
enum FocusQuietPolicy {
    /// Kinds of interruption the notch can hold back.
    enum Kind: String, CaseIterable, Sendable {
        case notification, message, call, agent, build

        func label(_ count: Int) -> String {
            let one: String, many: String
            switch self {
            case .notification: (one, many) = ("notification", "notifications")
            case .message: (one, many) = ("message", "messages")
            case .call: (one, many) = ("call", "calls")
            case .agent: (one, many) = ("agent update", "agent updates")
            case .build: (one, many) = ("build result", "build results")
            }
            return "\(count) \(count == 1 ? one : many)"
        }
    }

    /// Counts of what was held back during one focus block.
    struct Held: Equatable, Sendable {
        private(set) var counts: [Kind: Int] = [:]

        mutating func add(_ kind: Kind) { counts[kind, default: 0] += 1 }
        var total: Int { counts.values.reduce(0, +) }
        var isEmpty: Bool { total == 0 }
        func count(_ kind: Kind) -> Int { counts[kind] ?? 0 }
    }

    /// Quiet only while focus is actually running: a paused block means you
    /// stepped away, and breaks are for catching up.
    static func isQuiet(enabled: Bool, isActive: Bool, isPaused: Bool, phaseIsFocus: Bool) -> Bool {
        enabled && isActive && !isPaused && phaseIsFocus
    }

    /// Whether a kind is held while quiet. Calls can be let through.
    static func holds(_ kind: Kind, allowCalls: Bool) -> Bool {
        kind == .call ? !allowCalls : true
    }

    /// "While you focused: 3 notifications · 1 message", or nil if nothing came in.
    static func summary(_ held: Held) -> String? {
        let parts = Kind.allCases.compactMap { kind -> String? in
            let count = held.count(kind)
            return count > 0 ? kind.label(count) : nil
        }
        guard !parts.isEmpty else { return nil }
        return "While you focused: " + parts.joined(separator: " · ")
    }

    /// The tab that best shows what came in: messages if only messages did,
    /// otherwise the notification inbox (which also collects the others).
    enum Destination: Equatable, Sendable { case notifications, whatsapp, agents }

    static func destination(for held: Held) -> Destination {
        if held.total == held.count(.message), held.count(.message) > 0 { return .whatsapp }
        if held.total == held.count(.agent), held.count(.agent) > 0 { return .agents }
        return .notifications
    }
}
