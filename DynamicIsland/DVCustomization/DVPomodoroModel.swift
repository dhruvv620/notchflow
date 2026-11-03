// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation

@MainActor
final class DVPomodoroModel: ObservableObject {
    static let shared = DVPomodoroModel()
    private static let persistenceKey = "dv.pomodoro.v1"
    @Published private(set) var engine: DVPomodoroEngine
    @Published private(set) var secondsRemaining: Int
    private var ticker: AnyCancellable?

    private init() {
        let restored = UserDefaults.standard.data(forKey: Self.persistenceKey)
            .flatMap { try? JSONDecoder().decode(DVPomodoroEngine.self, from: $0) }
        var state = restored ?? DVPomodoroEngine()
        if state.configuration != state.configuration.normalized
            || (state.deadline.map { !$0.isFinite } ?? false)
            || !state.pausedRemaining.isFinite || state.completedFocusSessions < 0
            || state.completedFocusSessions > 12_000_000
            || (state.isRunning && state.deadline == nil) {
            state = DVPomodoroEngine()
        }
        _ = state.advance(to: Date().timeIntervalSince1970)
        engine = state
        secondsRemaining = Int(ceil(state.remaining(at: Date().timeIntervalSince1970)))
        configureTicker()
    }

    var timeText: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    var progress: Double {
        let duration = engine.configuration.duration(for: engine.phase)
        return min(1, max(0, 1 - Double(secondsRemaining) / duration))
    }

    func toggleRunning() {
        var state = engine
        let now = Date().timeIntervalSince1970
        if state.isRunning { state.pause(at: now) } else { state.start(at: now) }
        commit(state)
    }

    func reset() {
        var state = engine
        state.reset()
        commit(state)
    }

    func skip() {
        var state = engine
        state.skip(at: Date().timeIntervalSince1970)
        commit(state)
    }

    func setConfiguration(_ configuration: DVPomodoroConfiguration) {
        guard !engine.isRunning else { return }
        commit(DVPomodoroEngine(configuration: configuration))
    }

    private func configureTicker() {
        ticker = nil
        guard engine.isRunning else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
    }

    private func tick() {
        var state = engine
        let phaseChanged = state.advance(to: Date().timeIntervalSince1970)
        engine = state
        refreshRemaining()
        if phaseChanged {
            persist()
            if UserDefaults.standard.object(forKey: "dv.phaseSound") as? Bool ?? true {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        }
        if !state.isRunning { ticker = nil }
    }

    private func commit(_ state: DVPomodoroEngine) {
        engine = state
        refreshRemaining()
        persist()
        configureTicker()
    }

    private func refreshRemaining() {
        secondsRemaining = Int(ceil(engine.remaining(at: Date().timeIntervalSince1970)))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(engine) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }
}
