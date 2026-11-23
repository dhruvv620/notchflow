// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation

/// Gives Orbit's morning brief once a day at the chosen hour: one timer set
/// for that moment (no polling), and nothing at all while the brief is off.
@MainActor
final class OrbitBriefing {
    static let shared = OrbitBriefing()
    private var timer: Timer?
    private var isActive = false
    private var hour = -1

    private init() {}

    func setActive(_ active: Bool) {
        let newHour = Defaults[.orbitBriefHour]
        guard active != isActive || (active && newHour != hour) else { return }
        isActive = active
        hour = newHour
        timer?.invalidate()
        timer = nil
        guard active else { return }
        if OrbitTeamPolicy.briefIsDue(lastDay: Defaults[.orbitLastBriefDay], now: Date(), hour: newHour) {
            // Missed while the Mac was off: give it shortly, once things have loaded.
            schedule(at: Date().addingTimeInterval(30))
        } else {
            schedule(at: OrbitTeamPolicy.nextBriefDate(after: Date(), hour: newHour))
        }
    }

    private func schedule(at date: Date) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            Task { @MainActor in OrbitBriefing.shared.fire() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        guard isActive else { return }
        let now = Date()
        if OrbitTeamPolicy.briefIsDue(lastDay: Defaults[.orbitLastBriefDay], now: now, hour: hour),
           let brief = Orbit.shared.makeBrief() {
            Defaults[.orbitLastBriefDay] = brief.day
            NotificationHub.shared.post(id: "orbit-brief-\(brief.day)", appName: "Orbit",
                                        title: brief.headline, body: brief.lines.prefix(3).joined(separator: "\n"))
        }
        schedule(at: OrbitTeamPolicy.nextBriefDate(after: now.addingTimeInterval(60), hour: hour))
    }
}
