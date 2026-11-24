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
             detail: "Background checks run less often and wake the Mac together."),
        Item(id: "optimizer-React to events instead of polling", key: .optimizeUseEvents, title: "React to events instead of polling",
             detail: "Things update when they change, instead of being checked every second."),
        Item(id: "optimizer-Pause when nobody's looking", key: .optimizePauseWhenIdle, title: "Pause when nobody's looking",
             detail: "Background checks stop while the screen is locked or asleep."),
        Item(id: "optimizer-Save battery on battery power", key: .optimizeLowPower, title: "Save battery on battery power",
             detail: "Slower lyrics animation, no live visualizer, fewer checks."),
        Item(id: "optimizer-Calm endless animations", key: .optimizeCalmAnimations, title: "Calm endless animations",
             detail: "Pulsing dots pulse five times, then stay still."),
        Item(id: "optimizer-Keep memory in check", key: .optimizeBoundMemory, title: "Keep memory in check",
             detail: "Reads less of long agent chats and clears web caches when idle."),
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
                    SettingsStatus(text: conditionsText, kind: energy.conditions.saving ? .ok : .neutral)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Right now")
            }

            Section {
                ForEach(items, id: \.title) { item in
                    SettingsToggle(key: item.key, title: item.title, detail: item.detail, highlightID: item.id)
                }
                HStack {
                    Spacer()
                    Button("Turn All Off") { setAll(false) }
                    Button("Turn All On") { setAll(true) }
                        .settingsPrimaryButton()
                }
            } header: {
                Text("Ways to save")
            } footer: {
                Text("Each one works at once. For a before-and-after report, run tools/energy-report.sh in the NotchFlow folder.")
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
        if conditions.idle { parts.append("Mac idle, background work paused") }
        if energy.switches.lowPowerAdapt && conditions.saving { parts.append("saving battery") }
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
