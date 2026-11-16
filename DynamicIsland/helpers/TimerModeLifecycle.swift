// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum PomodoroPhase: String, Equatable, Sendable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
    var isBreak: Bool { self != .focus }
}

struct PomodoroConfiguration: Equatable, Sendable {
    let focusDuration: TimeInterval
    let shortBreakDuration: TimeInterval
    let longBreakDuration: TimeInterval
    let sessionsBeforeLongBreak: Int

    init(focusDuration: TimeInterval = 25 * 60,
         shortBreakDuration: TimeInterval = 5 * 60,
         longBreakDuration: TimeInterval = 15 * 60,
         sessionsBeforeLongBreak: Int = 4) {
        func duration(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
            value.isFinite ? min(max(value, 1), 24 * 60 * 60) : fallback
        }
        self.focusDuration = duration(focusDuration, fallback: 25 * 60)
        self.shortBreakDuration = duration(shortBreakDuration, fallback: 5 * 60)
        self.longBreakDuration = duration(longBreakDuration, fallback: 15 * 60)
        self.sessionsBeforeLongBreak = min(max(sessionsBeforeLongBreak, 1), 100)
    }

    var cycleDuration: TimeInterval {
        Double(sessionsBeforeLongBreak) * focusDuration
            + Double(sessionsBeforeLongBreak - 1) * shortBreakDuration
            + longBreakDuration
    }
}

/// Phase selection uses actual elapsed time, so delayed callbacks or waking from
/// sleep never lose seconds. Catch-up examines one cycle, not every missed phase.
struct PomodoroLifecycle: Sendable {
    let configuration: PomodoroConfiguration
    private(set) var phase: PomodoroPhase = .focus
    private(set) var completedFocusSessions = 0
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var deadline: Date?
    private var runStartedAt: Date?
    private var elapsedBeforeRun: TimeInterval = 0
    private var pausedRemaining: TimeInterval

    init(configuration: PomodoroConfiguration = PomodoroConfiguration()) {
        self.configuration = configuration
        pausedRemaining = configuration.focusDuration
    }

    var phaseDuration: TimeInterval {
        switch phase {
        case .focus: return configuration.focusDuration
        case .shortBreak: return configuration.shortBreakDuration
        case .longBreak: return configuration.longBreakDuration
        }
    }

    mutating func start(at now: Date) {
        reset()
        isActive = true
        runStartedAt = now
        _ = update(at: now)
    }

    mutating func pause(at now: Date) {
        guard isActive, !isPaused else { return }
        _ = update(at: now)
        elapsedBeforeRun = elapsed(at: now)
        pausedRemaining = sample(atElapsed: elapsedBeforeRun).remaining
        runStartedAt = nil
        isPaused = true
        deadline = nil
    }

    mutating func resume(at now: Date) {
        guard isActive, isPaused else { return }
        runStartedAt = now
        isPaused = false
        _ = update(at: now)
    }

    mutating func reset() {
        phase = .focus
        completedFocusSessions = 0
        isActive = false
        isPaused = false
        deadline = nil
        runStartedAt = nil
        elapsedBeforeRun = 0
        pausedRemaining = configuration.focusDuration
    }

    /// Returns true when phase or completed-focus count changed, even if a long
    /// sleep crossed a full cycle and landed on a phase with the same name.
    @discardableResult
    mutating func update(at now: Date) -> Bool {
        guard isActive, !isPaused else { return false }
        let value = sample(atElapsed: elapsed(at: now))
        let changed = phase != value.phase || completedFocusSessions != value.completed
        phase = value.phase
        completedFocusSessions = value.completed
        pausedRemaining = value.remaining
        deadline = now.addingTimeInterval(value.remaining)
        return changed
    }

    func remaining(at now: Date) -> TimeInterval {
        guard isActive else { return configuration.focusDuration }
        return isPaused ? pausedRemaining : sample(atElapsed: elapsed(at: now)).remaining
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard let runStartedAt else { return elapsedBeforeRun }
        let delta = now.timeIntervalSince(runStartedAt)
        guard delta.isFinite else { return elapsedBeforeRun }
        let total = elapsedBeforeRun + max(0, delta)
        return total.isFinite ? total : elapsedBeforeRun
    }

    private func sample(atElapsed elapsed: TimeInterval) -> (phase: PomodoroPhase, completed: Int, remaining: TimeInterval) {
        let cycle = configuration.cycleDuration
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let cycles = floor(elapsed / cycle)
        // Saturating display count also makes pathological injected dates safe.
        let countPerCycle = configuration.sessionsBeforeLongBreak
        let maxCycles = (Int.max - countPerCycle) / countPerCycle
        let completedCycles = cycles >= Double(maxCycles) ? maxCycles : Int(cycles)
        let baseCompleted = completedCycles * countPerCycle
        var position = elapsed.truncatingRemainder(dividingBy: cycle)
        for index in 0..<countPerCycle {
            if position < configuration.focusDuration {
                return (.focus, baseCompleted + index, configuration.focusDuration - position)
            }
            position -= configuration.focusDuration
            let last = index == countPerCycle - 1
            let duration = last ? configuration.longBreakDuration : configuration.shortBreakDuration
            if position < duration {
                return (last ? .longBreak : .shortBreak, baseCompleted + index + 1, duration - position)
            }
            position -= duration
        }
        // Floating-point subtraction at a cycle boundary may leave a tiny residue.
        return (.focus, baseCompleted + countPerCycle, configuration.focusDuration)
    }
}

/// A stopwatch stores time only at pause boundaries. No callback count is used,
/// and the model itself creates no timers or observers while idle or paused.
struct StopwatchLifecycle: Sendable {
    private(set) var hasStarted = false
    private var runStartedAt: Date?
    private var elapsedBeforeRun: TimeInterval = 0
    var isRunning: Bool { runStartedAt != nil }

    init() {}

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        hasStarted = true
        runStartedAt = now
    }
    mutating func resume(at now: Date) { start(at: now) }
    mutating func pause(at now: Date) {
        guard isRunning else { return }
        elapsedBeforeRun = elapsed(at: now)
        runStartedAt = nil
    }
    mutating func reset() {
        runStartedAt = nil
        elapsedBeforeRun = 0
        hasStarted = false
    }
    func elapsed(at now: Date) -> TimeInterval {
        guard let runStartedAt else { return elapsedBeforeRun }
        let delta = now.timeIntervalSince(runStartedAt)
        guard delta.isFinite else { return elapsedBeforeRun }
        let total = elapsedBeforeRun + max(0, delta)
        return total.isFinite ? total : elapsedBeforeRun
    }
}
