// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import Foundation
import SwiftUI

extension Defaults.Keys {
    static let focusHistoryData = Key<Data>("focusHistoryData", default: Data())
    /// Run a Shortcut to turn a Focus on during Pomodoro focus, and another after.
    static let pomodoroControlsFocus = Key<Bool>("pomodoroControlsFocus", default: false)
    static let pomodoroFocusOnShortcut = Key<String>("pomodoroFocusOnShortcut", default: "NotchFlow Focus On")
    static let pomodoroFocusOffShortcut = Key<String>("pomodoroFocusOffShortcut", default: "NotchFlow Focus Off")
}

/// Stores completed focus sessions and switches a Focus through Shortcuts.
@MainActor
final class FocusHistory: ObservableObject {
    static let shared = FocusHistory()

    @Published private(set) var records: [FocusSessionRecord] = []

    private init() {
        records = (try? JSONDecoder().decode([FocusSessionRecord].self, from: Defaults[.focusHistoryData])) ?? []
    }

    func recordFocus(minutes: Double, at date: Date = Date()) {
        records = FocusHistoryPolicy.appending(FocusSessionRecord(endedAt: date, minutes: minutes), to: records, now: date)
        if let data = try? JSONEncoder().encode(records) { Defaults[.focusHistoryData] = data }
    }

    var week: [(day: Date, minutes: Double)] { FocusHistoryPolicy.lastSevenDays(records, now: Date()) }
    var todayMinutes: Double { FocusHistoryPolicy.minutes(on: Date(), in: records) }
    var weekMinutes: Double { week.reduce(0) { $0 + $1.minutes } }
    var streak: Int { FocusHistoryPolicy.streak(records, now: Date()) }

    // MARK: Focus through Shortcuts

    private var focusIsOn = false

    /// Called when the Pomodoro enters a phase. Runs the user's shortcut that
    /// turns a Focus on at the start of focus, and the other one on breaks.
    func pomodoroEntered(_ phase: PomodoroPhase?) {
        guard Defaults[.pomodoroControlsFocus] else { return }
        let wantsFocus = phase == .focus
        guard wantsFocus != focusIsOn else { return }
        focusIsOn = wantsFocus
        let name = wantsFocus ? Defaults[.pomodoroFocusOnShortcut] : Defaults[.pomodoroFocusOffShortcut]
        Self.runShortcut(named: name)
    }

    static func runShortcut(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", trimmed]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}

/// Seven bars of focus minutes with today's total and the streak.
struct FocusWeekStrip: View {
    @ObservedObject private var history = FocusHistory.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        let week = history.week
        let peak = max(25, week.map(\.minutes).max() ?? 0)
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, entry in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == week.count - 1 ? appearance.accentColor : Color.white.opacity(entry.minutes > 0 ? 0.45 : 0.12))
                            .frame(width: 8, height: max(2, 22 * entry.minutes / peak))
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .help("\(entry.day.formatted(.dateTime.weekday(.wide))): \(FocusHistoryPolicy.durationLabel(minutes: entry.minutes))")
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Today \(FocusHistoryPolicy.durationLabel(minutes: history.todayMinutes))")
                    .font(.system(size: 10, weight: .semibold))
                Text("Week \(FocusHistoryPolicy.durationLabel(minutes: history.weekMinutes))" + (history.streak > 1 ? " · \(history.streak)-day streak" : ""))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus today \(FocusHistoryPolicy.durationLabel(minutes: history.todayMinutes)), this week \(FocusHistoryPolicy.durationLabel(minutes: history.weekMinutes))")
    }
}
