// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct TimerModeRegression {
    static func main() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "TimerModeRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func close(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool { abs(lhs - rhs) < 0.000_001 }
        let origin = Date(timeIntervalSince1970: 1_000_000)
        let config = PomodoroConfiguration(focusDuration: 25, shortBreakDuration: 5, longBreakDuration: 15, sessionsBeforeLongBreak: 4)
        var clock = PomodoroLifecycle(configuration: config)
        try require(!clock.isActive && clock.phase == .focus && close(clock.remaining(at: origin), 25), "Idle state is not a new focus session")
        clock.start(at: origin)
        try require(clock.isActive && !clock.isPaused && clock.deadline == origin.addingTimeInterval(25), "Focus did not start at its deadline")
        try require(close(clock.remaining(at: origin.addingTimeInterval(12.75)), 12.25), "Pomodoro used tick counts instead of elapsed time")
        try require(clock.update(at: origin.addingTimeInterval(25)), "Exact focus deadline did not change phase")
        try require(clock.phase == .shortBreak && clock.completedFocusSessions == 1 && close(clock.remaining(at: origin.addingTimeInterval(25)), 5), "First focus did not enter a short break")
        clock.update(at: origin.addingTimeInterval(30))
        try require(clock.phase == .focus && clock.completedFocusSessions == 1 && close(clock.remaining(at: origin.addingTimeInterval(30)), 25), "Exact break deadline did not start the next focus")
        clock.update(at: origin.addingTimeInterval(115))
        try require(clock.phase == .longBreak && clock.completedFocusSessions == 4 && close(clock.remaining(at: origin.addingTimeInterval(115)), 15), "Fourth focus did not start the long break")
        clock.update(at: origin.addingTimeInterval(130))
        try require(clock.phase == .focus && clock.completedFocusSessions == 4, "Long break did not start the next cycle")

        clock.reset()
        clock.start(at: origin)
        clock.pause(at: origin.addingTimeInterval(10))
        try require(clock.isPaused && clock.deadline == nil && close(clock.remaining(at: origin.addingTimeInterval(1_000)), 15), "Paused time continued counting")
        clock.resume(at: origin.addingTimeInterval(1_000))
        try require(clock.deadline == origin.addingTimeInterval(1_015), "Resume lost the paused remainder")
        clock.update(at: origin.addingTimeInterval(1_020))
        try require(clock.phase == .focus && clock.completedFocusSessions == 1, "Resume did not chain after focus and break")
        clock.reset()
        try require(!clock.isActive && !clock.isPaused && clock.completedFocusSessions == 0 && clock.deadline == nil, "Reset retained an active session")

        // Millions of missed cycles must be constant work per configured cycle,
        // not one loop for every missed timer callback or every elapsed phase.
        clock.start(at: origin)
        let cycles = 1_000_000
        let wake = origin.addingTimeInterval(Double(cycles) * config.cycleDuration + 27.5)
        clock.update(at: wake)
        try require(clock.phase == .shortBreak && clock.completedFocusSessions == cycles * 4 + 1 && close(clock.remaining(at: wake), 2.5), "Long sleep catch-up lost phase or completed-session count")
        let oneSession = PomodoroConfiguration(focusDuration: 10, shortBreakDuration: 3, longBreakDuration: 7, sessionsBeforeLongBreak: 1)
        var single = PomodoroLifecycle(configuration: oneSession)
        single.start(at: origin)
        single.update(at: origin.addingTimeInterval(10))
        try require(single.phase == .longBreak, "One-focus cycles should immediately use the long break")
        let invalid = PomodoroConfiguration(focusDuration: .nan, shortBreakDuration: -1, longBreakDuration: .infinity, sessionsBeforeLongBreak: 0)
        try require(invalid.focusDuration > 0 && invalid.shortBreakDuration > 0 && invalid.longBreakDuration.isFinite && invalid.sessionsBeforeLongBreak == 1, "Invalid configuration was not bounded")

        var stopwatch = StopwatchLifecycle()
        try require(!stopwatch.hasStarted && !stopwatch.isRunning && stopwatch.elapsed(at: origin) == 0, "Stopwatch is active before start")
        stopwatch.start(at: origin)
        stopwatch.start(at: origin.addingTimeInterval(5))
        try require(close(stopwatch.elapsed(at: origin.addingTimeInterval(120.125)), 120.125), "Stopwatch restarted or drifted when callbacks were absent")
        stopwatch.pause(at: origin.addingTimeInterval(120.125))
        try require(!stopwatch.isRunning && close(stopwatch.elapsed(at: origin.addingTimeInterval(5_000)), 120.125), "Paused stopwatch accrued elapsed time")
        stopwatch.resume(at: origin.addingTimeInterval(5_000))
        try require(close(stopwatch.elapsed(at: origin.addingTimeInterval(5_010.5)), 130.625), "Stopwatch resume discarded prior elapsed time")
        stopwatch.reset()
        try require(!stopwatch.hasStarted && !stopwatch.isRunning && stopwatch.elapsed(at: origin) == 0, "Stopwatch reset retained state")
        stopwatch.start(at: origin)
        try require(stopwatch.elapsed(at: origin.addingTimeInterval(-10)) == 0, "Clock reversal produced negative elapsed time")
        print("Pomodoro and stopwatch lifecycle checks passed")
    }
}
