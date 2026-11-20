// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// The Optimizer: what each of its switches changes, as plain rules.
/// Foundation only, so Build.command can check it alone.
enum EnergyPolicy {
    /// One switch per optimization (Settings > Optimizer).
    struct Switches: Equatable, Sendable {
        /// Wake up less often, and let macOS batch the wake-ups.
        var batchTimers = true
        /// React to events (file changes, mouse movement, tab changes) instead of polling.
        var useEvents = true
        /// Pause background work while the screen is locked or the displays sleep.
        var pauseWhenIdle = true
        /// On battery or in Low Power Mode: fewer frames, no live audio visualizer.
        var lowPowerAdapt = true
        /// Endless pulses run a few times, then rest; none on battery saver or when idle.
        var calmAnimations = true
        /// Keep less in memory and release caches when idle.
        var boundMemory = true

        static let allOff = Switches(batchTimers: false, useEvents: false, pauseWhenIdle: false, lowPowerAdapt: false,
                                     calmAnimations: false, boundMemory: false)
    }

    /// What the Mac is doing right now.
    struct Conditions: Equatable, Sendable {
        /// Screen locked, displays asleep or another user active.
        var idle = false
        var lowPowerMode = false
        var onBattery = false

        var saving: Bool { lowPowerMode || onBattery }
    }

    /// Background work that runs on a timer.
    enum Job: String, CaseIterable, Sendable {
        case clipboard, copyAction, meetings, buildJobs, agentFollow, bannerScan, notificationDatabase, timeTracking

        /// How often it runs without the Optimizer.
        var normalInterval: TimeInterval {
            switch self {
            case .clipboard: return 0.5
            case .copyAction: return 0.7
            case .meetings: return 1
            case .buildJobs: return 2
            case .agentFollow: return 1
            case .bannerScan: return 1.5
            case .notificationDatabase: return 2
            case .timeTracking: return 5
            }
        }

        /// How often it runs with "Batch and slow the timers" on.
        var batchedInterval: TimeInterval {
            switch self {
            case .clipboard: return 1
            case .copyAction: return 1
            case .meetings: return 20
            case .buildJobs: return 5
            case .agentFollow: return 2
            case .bannerScan: return 3
            case .notificationDatabase: return 5
            case .timeTracking: return 10
            }
        }

        /// Things you are looking at (a copy you just made) keep their pace on battery saver.
        var slowsOnBattery: Bool { self != .clipboard && self != .copyAction }
    }

    /// How long until the job runs again. `soon` keeps the meeting countdown
    /// ticking every second when a meeting is close.
    static func interval(for job: Job, switches: Switches, conditions: Conditions, soon: Bool = false) -> TimeInterval {
        if job == .meetings && soon { return 1 }
        var interval = switches.batchTimers ? job.batchedInterval : job.normalInterval
        if switches.lowPowerAdapt && conditions.saving && job.slowsOnBattery { interval *= 2 }
        return interval
    }

    /// How much later than asked macOS may run it, so wake-ups line up.
    static func tolerance(for interval: TimeInterval, switches: Switches) -> TimeInterval {
        switches.batchTimers ? interval * 0.25 : 0
    }

    /// Whether background work stops for now.
    static func isPaused(_ job: Job, switches: Switches, conditions: Conditions) -> Bool {
        switches.pauseWhenIdle && conditions.idle
    }

    /// The hover loop for "hide until hover": how long to wait between checks.
    static func hoverDelay(switches: Switches, secondsSinceMouseMoved: TimeInterval) -> TimeInterval {
        if switches.useEvents && secondsSinceMouseMoved > 2 { return 0.4 }
        return switches.batchTimers ? 0.1 : 0.05
    }

    /// Frames per second for the karaoke lyrics.
    static func lyricsFrameRate(switches: Switches, conditions: Conditions) -> Double {
        switches.lowPowerAdapt && conditions.saving ? 10 : 30
    }

    /// The live audio visualizer captures and analyzes sound all the time.
    static func allowsVisualizer(switches: Switches, conditions: Conditions) -> Bool {
        !(switches.lowPowerAdapt && conditions.saving)
    }

    /// How an endless animation (a pulse) should repeat: forever, a few times
    /// then rest, or not at all.
    enum Repeat: Equatable, Sendable { case forever, times(Int), none }

    static func pulse(switches: Switches, conditions: Conditions) -> Repeat {
        guard switches.calmAnimations else { return .forever }
        if conditions.idle || (switches.lowPowerAdapt && conditions.saving) { return .none }
        return .times(5)
    }

    /// How much of an agent conversation file is read, and how many messages are kept.
    static func transcriptTailBytes(switches: Switches) -> UInt64 { switches.boundMemory ? 1_048_576 : 4_194_304 }
    static func transcriptItemLimit(switches: Switches) -> Int { switches.boundMemory ? 150 : 300 }

    /// Release caches (web responses, decoded images) when the Mac goes idle.
    static func releasesCachesWhenIdle(switches: Switches) -> Bool { switches.boundMemory }

    /// Rough wake-ups per second from the timers, to show in Settings.
    static func estimatedWakeUps(switches: Switches, conditions: Conditions) -> Double {
        Job.allCases.reduce(0) { total, job in
            isPaused(job, switches: switches, conditions: conditions)
                ? total : total + 1 / interval(for: job, switches: switches, conditions: conditions)
        }
    }
}
