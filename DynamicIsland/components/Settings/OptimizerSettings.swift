// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Combine
import Defaults
import SwiftUI

/// Settings > Optimizer: one switch per way NotchFlow saves memory, CPU,
/// graphics and battery, each taking effect immediately, with a live readout.
struct OptimizerSettings: View {
    @ObservedObject private var energy = EnergySaver.shared
    @State private var memoryMB = EnergySaver.memoryFootprintMB()
    @State private var cpuPercent: Double?
    @State private var lastCPU = (seconds: EnergySaver.cpuSeconds(), at: Date())
    private let ticker = Timer.publish(every: 2, tolerance: 0.5, on: .main, in: .common).autoconnect()

    private struct Item {
        /// The search highlight id ("optimizer-<title>").
        let id: String
        let key: Defaults.Key<Bool>
        let title: String
        let detail: String
    }

    private let items: [Item] = [
        Item(id: "optimizer-Batch and slow the timers", key: .optimizeBatchTimers, title: "Batch and slow the timers",
             detail: "Background checks (clipboard, meetings, notifications, time tracking, build jobs) run less often, and macOS may line their wake-ups up. The meeting countdown still ticks every second when a meeting is near."),
        Item(id: "optimizer-React to events instead of polling", key: .optimizeUseEvents, title: "React to events instead of polling",
             detail: "An open agent conversation updates when its file changes instead of being re-read every second; hover detection rests while the mouse is still; time tracking asks the browser for its address only when the tab changes."),
        Item(id: "optimizer-Pause when nobody's looking", key: .optimizePauseWhenIdle, title: "Pause when nobody's looking",
             detail: "While the screen is locked, the displays sleep or another user is active, background checks stop completely."),
        Item(id: "optimizer-Save battery on battery power", key: .optimizeLowPower, title: "Save battery on battery power",
             detail: "On battery or in Low Power Mode: lyrics animate at 10 frames a second instead of 30, the live audio visualizer turns off, and background checks run half as often."),
        Item(id: "optimizer-Calm endless animations", key: .optimizeCalmAnimations, title: "Calm endless animations",
             detail: "Pulses (an agent waiting, the distraction meter, recording and privacy dots) pulse five times and then stay still; on battery saver or when idle they don't pulse. Loading spinners keep turning."),
        Item(id: "optimizer-Keep memory in check", key: .optimizeBoundMemory, title: "Keep memory in check",
             detail: "Reads the last 1 MB of long agent conversations (instead of 4 MB) and keeps 150 messages, and clears cached web responses when the Mac goes idle."),
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 18) {
                        stat("Memory", String(format: "%.0f MB", memoryMB))
                        stat("CPU", cpuPercent.map { String(format: "%.1f %%", $0) } ?? "…")
                        stat("Timer wake-ups", String(format: "~%.1f / s",
                                                      EnergyPolicy.estimatedWakeUps(switches: energy.switches, conditions: energy.conditions)))
                    }
                    Text(conditionsText)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Turn all on") { setAll(true) }
                    Button("Turn all off") { setAll(false) }
                    Spacer()
                }
            } header: {
                Text("NotchFlow right now")
            } footer: {
                Text("Each switch takes effect immediately. For a fuller before-and-after comparison, run tools/energy-report.sh in the NotchFlow folder.")
            }

            Section {
                ForEach(items, id: \.title) { item in
                    Defaults.Toggle(key: item.key) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: item.id)
                }
            } header: {
                Text("Optimizations")
            }
        }
        .onReceive(ticker) { _ in sample() }
        .onAppear { sample() }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var conditionsText: String {
        let conditions = energy.conditions
        var parts = [conditions.onBattery ? "On battery" : "On power adapter"]
        if conditions.lowPowerMode { parts.append("Low Power Mode on") }
        if conditions.idle { parts.append("Mac idle (background work paused)") }
        if energy.switches.lowPowerAdapt && conditions.saving { parts.append("battery saver active") }
        return parts.joined(separator: " · ")
    }

    private func sample() {
        memoryMB = EnergySaver.memoryFootprintMB()
        let now = Date(), seconds = EnergySaver.cpuSeconds()
        let wall = now.timeIntervalSince(lastCPU.at)
        if wall > 0.5 { cpuPercent = max(0, (seconds - lastCPU.seconds) / wall * 100) }
        lastCPU = (seconds, now)
    }

    private func setAll(_ on: Bool) {
        for item in items { Defaults[item.key] = on }
    }
}
