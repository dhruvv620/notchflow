// SPDX-License-Identifier: GPL-3.0-or-later
// Personal customization for Atoll. See the accompanying LICENSE.

import Foundation

enum DVPresentation: String, Codable, Equatable {
    case idle, preview, expanded
}

enum DVInteractionEvent {
    case hoverEntered, hoverExited, clicked, outsideClicked, cancelled
}

struct DVInteractionState: Equatable {
    private(set) var presentation: DVPresentation = .idle

    mutating func send(_ event: DVInteractionEvent) {
        switch event {
        case .clicked:
            presentation = .expanded
        case .outsideClicked, .cancelled:
            presentation = .idle
        case .hoverEntered:
            if presentation == .idle { presentation = .preview }
        case .hoverExited:
            if presentation == .preview { presentation = .idle }
        }
    }
}

enum DVPomodoroPhase: String, Codable, Equatable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

struct DVPomodoroConfiguration: Codable, Equatable {
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let sessionsBeforeLongBreak: Int

    init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5,
         longBreakMinutes: Int = 15, sessionsBeforeLongBreak: Int = 4) {
        self.focusMinutes = min(240, max(1, focusMinutes))
        self.shortBreakMinutes = min(60, max(1, shortBreakMinutes))
        self.longBreakMinutes = min(120, max(1, longBreakMinutes))
        self.sessionsBeforeLongBreak = min(12, max(1, sessionsBeforeLongBreak))
    }

    var normalized: Self {
        Self(focusMinutes: focusMinutes, shortBreakMinutes: shortBreakMinutes,
             longBreakMinutes: longBreakMinutes, sessionsBeforeLongBreak: sessionsBeforeLongBreak)
    }

    func duration(for phase: DVPomodoroPhase) -> TimeInterval {
        let c = normalized
        switch phase {
        case .focus: return Double(c.focusMinutes) * 60
        case .shortBreak: return Double(c.shortBreakMinutes) * 60
        case .longBreak: return Double(c.longBreakMinutes) * 60
        }
    }
}

/// Uses deadlines instead of decrementing a counter. Delayed timer callbacks and
/// sleep/wake therefore do not add timing drift. The UI supplies wall-clock time.
struct DVPomodoroEngine: Codable, Equatable {
    private(set) var configuration: DVPomodoroConfiguration
    private(set) var phase: DVPomodoroPhase = .focus
    private(set) var completedFocusSessions: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var deadline: TimeInterval?
    private(set) var pausedRemaining: TimeInterval

    init(configuration: DVPomodoroConfiguration = .init()) {
        self.configuration = configuration.normalized
        self.pausedRemaining = configuration.duration(for: .focus)
    }

    func remaining(at now: TimeInterval) -> TimeInterval {
        let raw = isRunning ? (deadline ?? now) - now : pausedRemaining
        guard raw.isFinite else { return configuration.duration(for: phase) }
        return min(configuration.duration(for: phase), max(0, raw))
    }

    mutating func start(at now: TimeInterval) {
        guard now.isFinite, !isRunning else { return }
        deadline = now + max(1, pausedRemaining)
        isRunning = true
    }

    mutating func pause(at now: TimeInterval) {
        guard isRunning, now.isFinite else { return }
        _ = advance(to: now)
        pausedRemaining = remaining(at: now)
        deadline = nil
        isRunning = false
    }

    /// Advances automatically into breaks and the next focus session. Whole
    /// cycles are skipped arithmetically after long sleeps, avoiding a huge loop.
    @discardableResult
    mutating func advance(to now: TimeInterval) -> Bool {
        guard isRunning, now.isFinite, let end = deadline, end.isFinite else { return false }
        guard now >= end else { return false }
        let c = configuration.normalized
        var changed = false
        while let currentEnd = deadline, currentEnd <= now {
            if phase == .focus {
                completedFocusSessions += 1
                phase = completedFocusSessions % c.sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
            } else {
                phase = .focus
            }
            deadline = currentEnd + c.duration(for: phase)
            pausedRemaining = c.duration(for: phase)
            changed = true

            if phase == .focus && completedFocusSessions % c.sessionsBeforeLongBreak == 0,
               let nextEnd = deadline {
                let cycle = Double(c.sessionsBeforeLongBreak) * c.duration(for: .focus)
                    + Double(c.sessionsBeforeLongBreak - 1) * c.duration(for: .shortBreak)
                    + c.duration(for: .longBreak)
                let cycles = floor(max(0, now - nextEnd) / cycle)
                // Dates beyond this range cannot occur in normal operation.
                // Stop malformed persisted data from overflowing integer counts.
                if cycles > 1_000_000 {
                    reset(configuration: c)
                    return true
                }
                let skipped = Int(cycles)
                if skipped > 0 {
                    completedFocusSessions += skipped * c.sessionsBeforeLongBreak
                    deadline = nextEnd + Double(skipped) * cycle
                }
            }
        }
        return changed
    }

    /// Skipping a focus interval does not count it as a completed session.
    mutating func skip(at now: TimeInterval) {
        guard now.isFinite else { return }
        if isRunning { _ = advance(to: now) }
        if phase == .focus {
            phase = .shortBreak
        } else {
            phase = .focus
        }
        pausedRemaining = configuration.duration(for: phase)
        deadline = isRunning ? now + pausedRemaining : nil
    }

    mutating func reset(configuration: DVPomodoroConfiguration? = nil) {
        self = Self(configuration: configuration ?? self.configuration)
    }
}
