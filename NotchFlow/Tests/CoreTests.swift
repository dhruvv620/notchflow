import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private var checks = 0
private func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
    checks += 1
    if !condition() { throw CheckFailure(description: description) }
}

@main
enum DVCoreTests {
    static func main() throws {
        var ui = DVInteractionState()
        try expect(ui.presentation == .idle, "Starts idle")
        ui.send(.hoverEntered)
        try expect(ui.presentation == .preview, "Hover opens only a preview")
        ui.send(.hoverExited)
        try expect(ui.presentation == .idle, "Leaving preview closes it")
        ui.send(.hoverEntered)
        ui.send(.clicked)
        try expect(ui.presentation == .expanded, "Click grows preview into full panel")
        ui.send(.hoverExited)
        try expect(ui.presentation == .expanded, "Leaving clicked panel keeps it open")
        ui.send(.hoverEntered)
        try expect(ui.presentation == .expanded, "Re-entering does not downgrade a clicked panel")
        ui.send(.outsideClicked)
        try expect(ui.presentation == .idle, "Outside click dismisses expanded panel")
        ui.send(.clicked)
        try expect(ui.presentation == .expanded, "A direct idle click also expands")
        ui.send(.cancelled)
        try expect(ui.presentation == .idle, "Escape or lock cancels")

        let config = DVPomodoroConfiguration(focusMinutes: 1, shortBreakMinutes: 1,
                                              longBreakMinutes: 2, sessionsBeforeLongBreak: 2)
        var timer = DVPomodoroEngine(configuration: config)
        timer.start(at: 100)
        try expect(timer.remaining(at: 159) == 1, "Deadline preserves exact remaining time")
        try expect(!timer.advance(to: 159), "Does not finish a phase early")
        try expect(timer.advance(to: 160), "Finishes on its exact deadline")
        try expect(timer.phase == .shortBreak && timer.completedFocusSessions == 1,
                   "A completed focus starts a short break")
        _ = timer.advance(to: 220)
        try expect(timer.phase == .focus && timer.remaining(at: 220) == 60,
                   "Automatically starts the next focus session")
        _ = timer.advance(to: 280)
        try expect(timer.phase == .longBreak && timer.completedFocusSessions == 2,
                   "Long break follows the configured number of completed sessions")
        _ = timer.advance(to: 400)
        try expect(timer.phase == .focus && timer.remaining(at: 400) == 60,
                   "Long break automatically returns to focus")

        timer.reset()
        timer.start(at: 0)
        timer.pause(at: 10)
        try expect(!timer.isRunning && timer.remaining(at: 1000) == 50,
                   "Pause preserves remaining time across a long delay")
        timer.start(at: 1000)
        try expect(timer.remaining(at: 1049) == 1, "Resume uses the saved remainder")
        _ = timer.advance(to: 1050)
        try expect(timer.phase == .shortBreak, "Resumed session ends at the new deadline")

        timer.reset()
        timer.start(at: 0)
        timer.skip(at: 10)
        try expect(timer.phase == .shortBreak && timer.completedFocusSessions == 0,
                   "Skipping focus does not count it as completed")
        try expect(timer.remaining(at: 10) == 60, "Skip starts a full next phase")

        var delayed = DVPomodoroEngine(configuration: .init(focusMinutes: 1,
            shortBreakMinutes: 1, longBreakMinutes: 1, sessionsBeforeLongBreak: 2))
        delayed.start(at: 0)
        _ = delayed.advance(to: 10_000_000)
        try expect(delayed.phase == .focus && delayed.completedFocusSessions == 83_333,
                   "Long sleep fast-forwards the correct phase and session count")
        try expect(delayed.remaining(at: 10_000_000) == 20,
                   "Long sleep introduces no accumulated timing drift")
        let beforeInvalid = delayed
        try expect(!delayed.advance(to: .infinity) && delayed == beforeInvalid,
                   "Non-finite times cannot corrupt a running timer")

        let saved = try JSONEncoder().encode(delayed)
        let restored = try JSONDecoder().decode(DVPomodoroEngine.self, from: saved)
        try expect(restored == delayed, "Persistence retains phase, deadline and session count")
        try expect(restored.remaining(at: 10_000_005) == 15,
                   "Restored running session continues against the same clock")

        let invalid = DVPomodoroConfiguration(focusMinutes: 0, shortBreakMinutes: -10,
            longBreakMinutes: 10000, sessionsBeforeLongBreak: 0)
        try expect(invalid.focusMinutes == 1 && invalid.shortBreakMinutes == 1
                   && invalid.longBreakMinutes == 120 && invalid.sessionsBeforeLongBreak == 1,
                   "Invalid configuration is clamped to supported bounds")
        delayed.reset(configuration: config)
        try expect(!delayed.isRunning && delayed.phase == .focus
                   && delayed.completedFocusSessions == 0 && delayed.remaining(at: 0) == 60,
                   "Reset clears a cycle and applies its configuration")
        print("Passed \(checks) interaction and Pomodoro checks.")
    }
}
