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

/// Keeps the notch quiet during a Pomodoro focus block, or a focus session
/// started from the moon button in the notch header. Pop-ups ask
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
    /// A focus session from the moon button: when it ends (`.distantFuture`
    /// until it is turned off), or nil when none is running.
    @Published private(set) var manualEnd: Date?
    private var pomodoroQuiet = false
    private var manualWork: DispatchWorkItem?
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
                guard let self else { return }
                self.pomodoroQuiet = FocusQuietPolicy.isQuiet(enabled: enabled, isActive: pomodoro.isActive,
                                                             isPaused: pomodoro.isPaused,
                                                             phaseIsFocus: pomodoro.phase == .focus)
                self.update(quiet: self.pomodoroQuiet || self.isManualActive)
            }
            .store(in: &cancellables)
    }

    // MARK: Focus sessions from the header

    var isManualActive: Bool { manualEnd.map { $0 > Date() } ?? false }

    /// Starts a focus session: `minutes` long, or until turned off (nil).
    /// With "Also silence macOS (Focus)" set up, macOS Focus turns on too.
    func startManual(minutes: Int?) {
        let end = minutes.map { Date().addingTimeInterval(TimeInterval($0) * 60) } ?? .distantFuture
        let wasActive = isManualActive
        withAnimation(.smooth(duration: 0.25)) { manualEnd = end }
        manualWork?.cancel()
        if let minutes {
            let work = DispatchWorkItem { [weak self] in self?.stopManual() }
            manualWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes) * 60, execute: work)
        }
        if !wasActive && Defaults[.pomodoroControlsFocus] && !pomodoroQuiet {
            FocusHistory.runShortcut(named: Defaults[.pomodoroFocusOnShortcut])
        }
        update(quiet: true)
    }

    func stopManual() {
        guard manualEnd != nil else { return }
        manualWork?.cancel()
        withAnimation(.smooth(duration: 0.25)) { manualEnd = nil }
        // A running Pomodoro focus block keeps macOS Focus on.
        if Defaults[.pomodoroControlsFocus] && !pomodoroQuiet {
            FocusHistory.runShortcut(named: Defaults[.pomodoroFocusOffShortcut])
        }
        update(quiet: pomodoroQuiet)
    }

    /// "Until you turn it off", or "24 min left".
    var manualRemainingText: String? {
        guard let end = manualEnd, isManualActive else { return nil }
        guard end != .distantFuture else { return "Until you turn it off" }
        let minutes = max(1, Int((end.timeIntervalSinceNow / 60).rounded(.up)))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min left" : "\(minutes) min left"
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

/// The moon button in the notch header: click for a focus session until you
/// click again, hold for a timed one.
struct FocusSessionButton: View {
    @ObservedObject private var quiet = FocusQuiet.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        let active = quiet.isManualActive
        Menu {
            if active {
                Button("End focus session") { quiet.stopManual() }
                Divider()
            }
            Button("Focus for 30 minutes") { quiet.startManual(minutes: 30) }
            Button("Focus for 1 hour") { quiet.startManual(minutes: 60) }
            Button("Focus for 2 hours") { quiet.startManual(minutes: 120) }
            Button("Focus until I turn it off") { quiet.startManual(minutes: nil) }
        } label: {
            Capsule()
                .fill(active ? appearance.accentColor.opacity(0.35) : Color.white.opacity(0.055))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: active ? "moon.fill" : "moon")
                        .foregroundColor(active ? appearance.accentColor : .white)
                        .imageScale(.medium)
                }
        } primaryAction: {
            if active { quiet.stopManual() } else { quiet.startManual(minutes: nil) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(active
              ? "Focus is on (\(quiet.manualRemainingText ?? "")): notifications, messages and calls wait. Click to end."
              : "Focus: click so nothing in the notch disturbs you until you click again. Hold for 30 min, 1 or 2 hours.")
        .accessibilityLabel(active ? "End focus session" : "Start focus session")
    }
}
