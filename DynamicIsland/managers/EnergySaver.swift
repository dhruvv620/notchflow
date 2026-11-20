// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import IOKit.ps
import SwiftUI

extension Defaults.Keys {
    // Settings > Optimizer. Each switch takes effect immediately.
    static let optimizeBatchTimers = Key<Bool>("optimizeBatchTimers", default: true)
    static let optimizeUseEvents = Key<Bool>("optimizeUseEvents", default: true)
    static let optimizePauseWhenIdle = Key<Bool>("optimizePauseWhenIdle", default: true)
    static let optimizeLowPower = Key<Bool>("optimizeLowPower", default: true)
    static let optimizeCalmAnimations = Key<Bool>("optimizeCalmAnimations", default: true)
    static let optimizeBoundMemory = Key<Bool>("optimizeBoundMemory", default: true)
}

extension Notification.Name {
    /// Posted on the main thread whenever a switch or the Mac's state changes.
    static let energyPolicyChanged = Notification.Name("NotchFlow.EnergyPolicyChanged")
    static let energyPowerSourceChanged = Notification.Name("NotchFlow.EnergyPowerSourceChanged")
}

/// The Optimizer's current switches and conditions, readable from any thread
/// (written on the main thread only).
enum EnergyState {
    nonisolated(unsafe) static var switches = EnergyPolicy.Switches()
    nonisolated(unsafe) static var conditions = EnergyPolicy.Conditions()
    nonisolated(unsafe) static var lastMouseMove = Date()

    static func interval(_ job: EnergyPolicy.Job, soon: Bool = false) -> TimeInterval {
        EnergyPolicy.interval(for: job, switches: switches, conditions: conditions, soon: soon)
    }
    static func isPaused(_ job: EnergyPolicy.Job) -> Bool {
        EnergyPolicy.isPaused(job, switches: switches, conditions: conditions)
    }
    static var allowsVisualizer: Bool { EnergyPolicy.allowsVisualizer(switches: switches, conditions: conditions) }
    static var hoverDelay: TimeInterval {
        EnergyPolicy.hoverDelay(switches: switches, secondsSinceMouseMoved: Date().timeIntervalSince(lastMouseMove))
    }

    /// An endless animation (a pulse) as the Optimizer allows it: forever,
    /// five times (odd, so it ends on its final state), or none (the view just
    /// shows its end state).
    static func repeating(_ base: Animation, autoreverses: Bool = true) -> Animation? {
        switch EnergyPolicy.pulse(switches: switches, conditions: conditions) {
        case .forever: return base.repeatForever(autoreverses: autoreverses)
        case .times(let count): return base.repeatCount(count, autoreverses: autoreverses)
        case .none: return nil
        }
    }
}

/// Watches what the Optimizer depends on (lock, display sleep, Low Power
/// Mode, battery) and its switches, and tells everything that cares.
@MainActor
final class EnergySaver: ObservableObject {
    static let shared = EnergySaver()

    @Published private(set) var switches = EnergyPolicy.Switches()
    @Published private(set) var conditions = EnergyPolicy.Conditions()

    private var displaysAsleep = false
    private var sessionInactive = false
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    private var powerSource: CFRunLoopSource?
    private var visualizerStopped = false
    private var started = false
    private var applied = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let keys: [Defaults.Key<Bool>] = [.optimizeBatchTimers, .optimizeUseEvents, .optimizePauseWhenIdle, .optimizeLowPower,
                                          .optimizeCalmAnimations, .optimizeBoundMemory]
        Publishers.MergeMany(keys.map { Defaults.publisher($0).map { _ in () }.eraseToAnyPublisher() })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        LockScreenManager.shared.$isLocked
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        let watch: [(NotificationCenter, Notification.Name, @MainActor (EnergySaver) -> Void)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, { $0.displaysAsleep = true }),
            (workspace, NSWorkspace.screensDidWakeNotification, { $0.displaysAsleep = false }),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, { $0.sessionInactive = true }),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, { $0.sessionInactive = false }),
            (NotificationCenter.default, Notification.Name.NSProcessInfoPowerStateDidChange, { _ in }),
            (NotificationCenter.default, .energyPowerSourceChanged, { _ in }),
        ]
        for (center, name, change) in watch {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(self)
                    self.refresh()
                }
            })
        }
        // Plugging in or unplugging the power adapter.
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .energyPowerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        refresh()
    }

    /// Reads the switches and the Mac's state, and applies them.
    func refresh() {
        let nextSwitches = EnergyPolicy.Switches(
            batchTimers: Defaults[.optimizeBatchTimers], useEvents: Defaults[.optimizeUseEvents],
            pauseWhenIdle: Defaults[.optimizePauseWhenIdle], lowPowerAdapt: Defaults[.optimizeLowPower],
            calmAnimations: Defaults[.optimizeCalmAnimations], boundMemory: Defaults[.optimizeBoundMemory])
        let nextConditions = EnergyPolicy.Conditions(
            idle: LockScreenManager.shared.isLocked || displaysAsleep || sessionInactive,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            onBattery: Self.isOnBattery())
        guard nextSwitches != switches || nextConditions != conditions || !applied else { return }
        applied = true
        let becameIdle = nextConditions.idle && !conditions.idle
        switches = nextSwitches
        conditions = nextConditions
        EnergyState.switches = nextSwitches
        EnergyState.conditions = nextConditions

        updateMouseMonitors()
        updateVisualizer()
        if becameIdle && EnergyPolicy.releasesCachesWhenIdle(switches: nextSwitches) { releaseCaches() }
        AppDelegate.shared?.refreshWindowForLayoutChange()
        NotificationCenter.default.post(name: .energyPolicyChanged, object: nil)
    }

    private static func isOnBattery() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    /// Mouse movement tells the hover loop when to look closely.
    private func updateMouseMonitors() {
        let wanted = switches.useEvents
        if wanted && mouseMonitors.isEmpty {
            let note: (NSEvent) -> Void = { _ in EnergyState.lastMouseMove = Date() }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: note) {
                mouseMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
                EnergyState.lastMouseMove = Date()
                return event
            }) {
                mouseMonitors.append(local)
            }
        } else if !wanted && !mouseMonitors.isEmpty {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors = []
        }
    }

    /// The live audio visualizer stops on battery saver and comes back after.
    private func updateVisualizer() {
        if !EnergyState.allowsVisualizer {
            if AudioTap.shared.isCapturing {
                AudioTap.shared.stopCapture()
                visualizerStopped = true
            }
        } else if visualizerStopped {
            visualizerStopped = false
            if Defaults[.enableRealTimeWaveform] { Task { await AudioTap.shared.startCapture() } }
        }
    }

    private func releaseCaches() {
        URLCache.shared.removeAllCachedResponses()
    }

    // MARK: Live usage, for Settings

    /// NotchFlow's memory footprint in megabytes (what Activity Monitor shows).
    nonisolated static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// CPU time used so far (user + system), in seconds.
    nonisolated static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}

/// A repeating timer that follows the Optimizer: its interval and tolerance
/// come from EnergyPolicy, it pauses while the Mac is idle, and it re-arms
/// as soon as a switch changes. Use it from the main thread.
final class EnergyTimer {
    private let job: EnergyPolicy.Job
    private let soon: (@MainActor () -> Bool)?
    private let fire: @MainActor () -> Void
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    init(_ job: EnergyPolicy.Job, soon: (@MainActor () -> Bool)? = nil, fire: @escaping @MainActor () -> Void) {
        self.job = job
        self.soon = soon
        self.fire = fire
    }

    /// The interval in use right now.
    var currentInterval: TimeInterval { EnergyState.interval(job) }

    func start() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .energyPolicyChanged, object: nil, queue: .main) { [weak self] _ in
                self?.arm()
            }
        }
        arm()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func arm() {
        timer?.invalidate()
        timer = nil
        guard !EnergyState.isPaused(job) else { return }  // re-armed when the Mac wakes
        let isSoon = soon.map { check in MainActor.assumeIsolated { check() } } ?? false
        let interval = EnergyState.interval(job, soon: isSoon)
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.fire() }
            self.arm()
        }
        next.tolerance = EnergyPolicy.tolerance(for: interval, switches: EnergyState.switches)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
}
