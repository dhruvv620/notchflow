// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// While a Pomodoro focus block runs, hold notifications, messages and other pop-ups.
    static let pomodoroHoldsInterruptions = Key<Bool>("pomodoroHoldsInterruptions", default: true)
    /// Let incoming calls through during focus.
    static let pomodoroAllowsCalls = Key<Bool>("pomodoroAllowsCalls", default: false)
}

/// Keeps the notch quiet during a Pomodoro focus block. Pop-ups ask
/// `shouldHold(_:)` before they appear; what was held still lands in its tab,
/// and a one-line summary shows when the block ends.
@MainActor
final class FocusQuiet: ObservableObject {
    static let shared = FocusQuiet()

    @Published private(set) var isQuiet = false
    /// "While you focused: …", shown for a few seconds after a block.
    @Published private(set) var summary: String?
    /// How many things came in during the last block.
    @Published private(set) var lastTotal = 0
    private(set) var held = FocusQuietPolicy.Held()
    private var lastHeld = FocusQuietPolicy.Held()

    private var cancellables = Set<AnyCancellable>()
    private var summaryWork: DispatchWorkItem?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        TimerModesManager.shared.$pomodoro
            .combineLatest(Defaults.publisher(.pomodoroHoldsInterruptions).map(\.newValue))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pomodoro, enabled in
                self?.update(quiet: FocusQuietPolicy.isQuiet(enabled: enabled, isActive: pomodoro.isActive,
                                                             isPaused: pomodoro.isPaused,
                                                             phaseIsFocus: pomodoro.phase == .focus))
            }
            .store(in: &cancellables)
    }

    /// Called where a pop-up would appear. True means stay quiet; the pop-up
    /// is counted for the summary.
    func shouldHold(_ kind: FocusQuietPolicy.Kind) -> Bool {
        guard isQuiet, FocusQuietPolicy.holds(kind, allowCalls: Defaults[.pomodoroAllowsCalls]) else { return false }
        held.add(kind)
        return true
    }

    /// For views that re-check every frame (calls): no counting.
    func holds(_ kind: FocusQuietPolicy.Kind) -> Bool {
        isQuiet && FocusQuietPolicy.holds(kind, allowCalls: Defaults[.pomodoroAllowsCalls])
    }

    private func update(quiet: Bool) {
        guard quiet != isQuiet else { return }
        withAnimation(.smooth(duration: 0.25)) { isQuiet = quiet }
        if quiet {
            held = FocusQuietPolicy.Held()
            dismissSummary()
        } else {
            lastHeld = held
            lastTotal = held.total
            held = FocusQuietPolicy.Held()
            showSummary(FocusQuietPolicy.summary(lastHeld))
        }
    }

    private func showSummary(_ text: String?) {
        guard let text else { return }
        withAnimation(.smooth(duration: 0.25)) { summary = text }
        summaryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissSummary() }
        summaryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    func dismissSummary() {
        summaryWork?.cancel()
        if summary != nil { withAnimation(.smooth(duration: 0.25)) { summary = nil } }
    }

    /// The tab that shows what came in during the block.
    var summaryDestination: NotchViews {
        switch FocusQuietPolicy.destination(for: lastHeld) {
        case .notifications: return .notifications
        case .whatsapp: return .whatsapp
        case .agents: return .agents
        }
    }
}

/// The line under the closed notch after a focus block: what came in.
struct FocusQuietSummaryActivity: View {
    @ObservedObject private var quiet = FocusQuiet.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    let isHovering: Bool

    var body: some View {
        ClosedNotchWings(isHovering: isHovering) {
            Image(systemName: "moon.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
            Text("Focus done")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        } trailing: {
            Text(shortCount)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quiet.summary ?? "Focus done")
        .help(quiet.summary ?? "")
    }

    /// "4 new", short enough for the wing; the full line is in the tooltip.
    private var shortCount: String {
        quiet.lastTotal > 0 ? "\(quiet.lastTotal) new" : ""
    }
}
