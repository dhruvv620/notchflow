// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import SwiftUI

/// One active Pomodoro clock, mirrored into the existing timer/live-activity UI.
/// Stopwatch elapsed time is derived from dates and needs no background ticker.
@MainActor
final class TimerModesManager: ObservableObject {
    static let shared = TimerModesManager()
    @Published private(set) var pomodoro = PomodoroLifecycle()
    @Published private(set) var stopwatch = StopwatchLifecycle()
    private var ownedSessionID: UUID?
    private var ticker: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?
    private let timer = TimerManager.shared

    private init() {
        Publishers.Merge3(
            timer.$activeSessionID.map { _ in true },
            timer.$isTimerActive.map { _ in true },
            timer.$isPaused.map { _ in true }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.reconcileTimerControls() }
        .store(in: &subscriptions)
    }

    var ownsDisplayedTimer: Bool {
        pomodoro.isActive && timer.isTimerActive && ownedSessionID != nil && ownedSessionID == timer.activeSessionID
    }

    func startPomodoro(configuration: PomodoroConfiguration) {
        stopTicker()
        var next = PomodoroLifecycle(configuration: configuration)
        next.start(at: Date())
        pomodoro = next
        mirrorNewPhase(at: Date())
        startTicker()
    }

    func pausePomodoro() {
        guard ownsDisplayedTimer else { return }
        var next = pomodoro
        next.pause(at: Date())
        pomodoro = next
        timer.pauseTimer()
        syncMirror(at: Date())
        stopTicker()
    }

    func resumePomodoro() {
        guard ownsDisplayedTimer else { return }
        var next = pomodoro
        next.resume(at: Date())
        pomodoro = next
        timer.resumeTimer()
        syncMirror(at: Date())
        startTicker()
    }

    func stopPomodoro(stopDisplayedTimer: Bool = true) {
        let shouldStopTimer = stopDisplayedTimer && ownsDisplayedTimer
        ownedSessionID = nil
        stopTicker()
        var next = pomodoro
        next.reset()
        pomodoro = next
        if shouldStopTimer { timer.forceStopTimer() }
    }

    func startNormalTimer(duration: TimeInterval) {
        stopPomodoro(stopDisplayedTimer: false)
        timer.startTimer(duration: duration, name: "Timer")
    }

    func startStopwatch() {
        var next = stopwatch
        next.start(at: Date())
        stopwatch = next
    }
    func pauseStopwatch() {
        var next = stopwatch
        next.pause(at: Date())
        stopwatch = next
    }
    func resetStopwatch() {
        var next = stopwatch
        next.reset()
        stopwatch = next
    }

    private func startTicker() {
        guard ticker == nil, pomodoro.isActive, !pomodoro.isPaused else { return }
        let ticker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(at: Date()) }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.tick(at: Date()) } }
    }
    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func tick(at now: Date) {
        // Compact live-activity controls publish their pause state asynchronously.
        // Apply it before mirroring, so a simultaneous tick cannot undo that tap.
        reconcileTimerControls()
        guard ownsDisplayedTimer else {
            if pomodoro.isActive { stopPomodoro(stopDisplayedTimer: false) }
            return
        }
        guard !pomodoro.isPaused else { return }
        var next = pomodoro
        let changed = next.update(at: now)
        pomodoro = next
        if changed {
            mirrorNewPhase(at: now)
            timer.playManagedPhaseSound()
        } else { syncMirror(at: now) }
    }

    private func mirrorNewPhase(at now: Date) {
        timer.startManagedTimer(duration: pomodoro.phaseDuration, name: "Pomodoro · \(pomodoro.phase.title)")
        ownedSessionID = timer.activeSessionID
        syncMirror(at: now)
    }
    private func syncMirror(at now: Date) {
        guard ownsDisplayedTimer else { return }
        timer.updateManagedTimer(remaining: pomodoro.remaining(at: now), duration: pomodoro.phaseDuration,
                                 paused: pomodoro.isPaused, name: "Pomodoro · \(pomodoro.phase.title)")
    }
    private func reconcileTimerControls() {
        guard pomodoro.isActive else { return }
        guard ownsDisplayedTimer && timer.isTimerActive else {
            stopPomodoro(stopDisplayedTimer: false)
            return
        }
        if timer.isPaused && !pomodoro.isPaused { pausePomodoro() }
        else if !timer.isPaused && pomodoro.isPaused { resumePomodoro() }
    }
}
