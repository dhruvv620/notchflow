// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct EnergyRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "EnergyRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = EnergyPolicy
        let on = P.Switches(), off = P.Switches.allOff
        let normal = P.Conditions(), battery = P.Conditions(onBattery: true), idle = P.Conditions(idle: true)

        // Batching slows every timer and adds tolerance; off keeps today's pace.
        for job in P.Job.allCases {
            let fast = P.interval(for: job, switches: off, conditions: normal)
            let slow = P.interval(for: job, switches: on, conditions: normal)
            try require(fast == job.normalInterval, "\(job) changed with the Optimizer off")
            try require(slow >= fast, "\(job) got faster with batching")
            try require(P.tolerance(for: slow, switches: on) > 0 && P.tolerance(for: fast, switches: off) == 0, "\(job) tolerance")
        }
        // A meeting that is close keeps its one-second countdown.
        try require(P.interval(for: .meetings, switches: on, conditions: normal, soon: true) == 1, "Meeting countdown slowed")
        try require(P.interval(for: .meetings, switches: on, conditions: normal) == 20, "Meeting check not slowed")
        // Battery saver doubles background jobs but not the clipboard.
        try require(P.interval(for: .bannerScan, switches: on, conditions: battery) == 6, "Battery did not slow the banner scan")
        try require(P.interval(for: .clipboard, switches: on, conditions: battery) == 1, "Battery slowed the clipboard")
        try require(P.interval(for: .bannerScan, switches: off, conditions: battery) == 1.5, "Battery slowed with the switch off")

        // Pausing while idle, only with its switch.
        try require(P.isPaused(.clipboard, switches: on, conditions: idle) && !P.isPaused(.clipboard, switches: off, conditions: idle), "Idle pause")
        try require(!P.isPaused(.clipboard, switches: on, conditions: normal), "Paused while in use")
        try require(P.estimatedWakeUps(switches: on, conditions: idle) == 0, "Wake-ups while idle")
        // About 7.3 timer wake-ups a second become about 3.4, before tolerance lets macOS merge them.
        try require(P.estimatedWakeUps(switches: on, conditions: normal) < P.estimatedWakeUps(switches: off, conditions: normal) / 2,
                    "Batching should halve timer wake-ups")

        // Hover polling backs off when the mouse is still.
        try require(P.hoverDelay(switches: off, secondsSinceMouseMoved: 10) == 0.05, "Hover delay off")
        try require(P.hoverDelay(switches: on, secondsSinceMouseMoved: 0.5) == 0.1, "Hover delay while moving")
        try require(P.hoverDelay(switches: on, secondsSinceMouseMoved: 10) == 0.4, "Hover delay while still")

        // Battery saver: fewer frames, no visualizer.
        try require(P.lyricsFrameRate(switches: on, conditions: battery) == 10 && P.lyricsFrameRate(switches: on, conditions: normal) == 30, "Lyrics frames")
        try require(!P.allowsVisualizer(switches: on, conditions: P.Conditions(lowPowerMode: true)) && P.allowsVisualizer(switches: off, conditions: battery), "Visualizer")

        // Pulses.
        try require(P.pulse(switches: off, conditions: battery) == .forever, "Pulse with the switch off")
        try require(P.pulse(switches: on, conditions: normal) == .times(5), "Pulse calmed")
        try require(P.pulse(switches: on, conditions: battery) == .none && P.pulse(switches: on, conditions: idle) == .none, "Pulse stopped")

        // Window and memory.
        try require(P.keepsWindowHeadroom(switches: on, isOpen: true) && !P.keepsWindowHeadroom(switches: on, isOpen: false), "Window headroom")
        try require(P.keepsWindowHeadroom(switches: off, isOpen: false), "Window headroom with the switch off")
        try require(P.transcriptTailBytes(switches: on) < P.transcriptTailBytes(switches: off), "Transcript tail")
        try require(P.transcriptItemLimit(switches: on) < P.transcriptItemLimit(switches: off), "Transcript items")
        print("Optimizer: OK")
    }
}
