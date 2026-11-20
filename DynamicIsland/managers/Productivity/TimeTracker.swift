// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import Combine
import UniformTypeIdentifiers
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Track which apps, sites and projects your time goes to (on this Mac only).
    static let enableTimeTracking = Key<Bool>("enableTimeTracking", default: true)
    /// Read the address of the front browser tab, so sites are told apart.
    static let timeTrackingSites = Key<Bool>("timeTrackingSites", default: true)
    /// The daily work goal, in hours.
    static let timeTrackingGoalHours = Key<Double>("timeTrackingGoalHours", default: 4)
    /// Which categories count as work (TimeCategory raw values).
    static let timeTrackingWorkCategories = Key<[String]>("timeTrackingWorkCategories",
                                                          default: TimeCategory.defaultWork.map(\.rawValue).sorted())
    /// Show the work ring under the closed notch when nothing else is there.
    static let timeTrackingShowRing = Key<Bool>("timeTrackingShowRing", default: true)
    /// Extra project names to recognize in window titles, comma separated.
    static let timeTrackingProjects = Key<String>("timeTrackingProjects", default: "")
    /// Show the weekly report under the notch on Friday afternoon.
    static let timeTrackingWeeklyReport = Key<Bool>("timeTrackingWeeklyReport", default: true)
    static let timeTrackingLastReportWeek = Key<String>("timeTrackingLastReportWeek", default: "")
}

/// Tracks where the day goes: every few seconds it notes the front app (the
/// site for browsers, the project from the window title) and adds the time
/// to today's log. Idle time, a locked screen and sleep are not counted.
/// Logs stay on this Mac, one JSON file per day.
@MainActor
final class TimeTracker: ObservableObject {
    static let shared = TimeTracker()

    /// Today's totals as shown; refreshed every 30 seconds so the notch is
    /// not redrawn on every sample.
    @Published private(set) var today: TimeDayLog
    /// Set when the weekly report is clicked, so the Flow tab opens on the week.
    @Published var showWeekRequested = false
    private var log: TimeDayLog
    private var lastPublish = Date.distantPast
    /// The Friday report, shown under the closed notch for a moment.
    @Published private(set) var weeklyReportReady = false

    private var timer: EnergyTimer?
    /// The front window last asked about, to skip asking the browser again
    /// while nothing changed (Optimizer: react to events).
    private var lastProbe: (key: String, at: Date)?
    private var lastTick: Date?
    private var lastSave = Date()
    private var isAsleep = false
    private var probing = false
    private var lastHost: (bundleID: String, host: String?)?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var reportWork: DispatchWorkItem?

    private init() {
        let loaded = Self.load(day: TimeTrackingPolicy.dayKey(Date())) ?? TimeDayLog(day: TimeTrackingPolicy.dayKey(Date()))
        log = loaded
        today = loaded
    }

    private func publish() {
        lastPublish = Date()
        if today != log { today = log }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleep = true; self?.save() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleep = false; self?.lastTick = nil }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        })
        // Every 5 s, or 10 s batched; paused while the Mac is idle.
        let timer = EnergyTimer(.timeTracking) { [weak self] in self?.tick(now: Date()) }
        timer.start()
        self.timer = timer
        Self.pruneOldLogs()
    }

    // MARK: Sampling

    private func tick(now: Date) {
        rollOverIfNeeded(now: now)
        checkWeeklyReport(now: now)
        guard Defaults[.enableTimeTracking], !isAsleep else { lastTick = nil; return }
        let interval = EnergyState.interval(.timeTracking)
        let gap = max(now.timeIntervalSince(lastTick ?? now), 0)
        // A long gap means sampling was paused (locked, asleep): count nothing for it.
        let elapsed = gap > interval * 3 ? 0 : min(gap, interval * 2)
        lastTick = now
        guard elapsed > 0, let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }
        let windowTitle = Self.frontWindowTitle(of: app)

        // Browsers: ask for the tab's address (at most one request at a time).
        // With "react to events", only when the window title changed (a new
        // tab or page) or a minute passed.
        var host: String?
        if Defaults[.timeTrackingSites], let script = FocusGuardManager.browserScripts[bundleID] {
            host = lastHost?.bundleID == bundleID ? lastHost?.host : nil
            let key = bundleID + "|" + (windowTitle ?? "")
            let unchanged = EnergyState.switches.useEvents && lastProbe?.key == key
                && now.timeIntervalSince(lastProbe?.at ?? .distantPast) < 60 && lastHost?.bundleID == bundleID
            if !probing && !unchanged {
                lastProbe = (key, now)
                probing = true
                Task { @MainActor [weak self] in
                    let address = try? await AppleScriptHelper.execute(script)?.stringValue
                    guard let self else { return }
                    self.probing = false
                    self.lastHost = (bundleID, address.flatMap(URL.init(string:))?.host)
                }
            }
        }
        let sample = TimeSample(bundleID: bundleID, appName: app.localizedName ?? bundleID,
                                windowTitle: windowTitle, host: host)
        let category = TimeTrackingPolicy.category(for: sample)
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard TimeTrackingPolicy.shouldCount(idleSeconds: idle, category: category, locked: LockScreenManager.shared.isLocked) else { return }

        let project = TimeTrackingPolicy.project(in: sample.windowTitle, bundleID: bundleID, known: knownProjects)
        let hour = Calendar.current.component(.hour, from: now)
        log.add(seconds: elapsed, category: category, label: TimeTrackingPolicy.label(for: sample), project: project, hour: hour)
        if now.timeIntervalSince(lastPublish) >= 30 { publish() }
        if now.timeIntervalSince(lastSave) > 60 { save() }
    }

    /// The front window's title, through Accessibility (already granted for
    /// the HUDs). Without it, projects are not detected.
    private static func frontWindowTitle(of app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    /// Project names from agent sessions and Settings.
    private var knownProjects: [String] {
        let fromAgents = Defaults[.agentRecentProjects].map { ($0 as NSString).lastPathComponent }
        let fromSessions = AgentConversations.shared.recent.map(\.project)
        let fromSettings = Defaults[.timeTrackingProjects].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return Array(Set(fromAgents + fromSessions + fromSettings)).filter { !$0.isEmpty && $0 != "Home" }
    }

    private func rollOverIfNeeded(now: Date) {
        let key = TimeTrackingPolicy.dayKey(now)
        guard key != log.day else { return }
        save()
        log = TimeDayLog(day: key)
        publish()
    }

    // MARK: Reports

    var workCategories: Set<TimeCategory> { TimeTrackingPolicy.workCategories(from: Defaults[.timeTrackingWorkCategories]) }
    var workToday: Double { today.work(workCategories) }
    var goalSeconds: Double { max(0.25, Defaults[.timeTrackingGoalHours]) * 3600 }
    var goalProgress: Double { min(1, workToday / goalSeconds) }

    /// The last 14 days, today included.
    func recentLogs(days: Int = 14) -> [TimeDayLog] {
        let calendar = Calendar.current
        return (0..<days).compactMap { offset -> TimeDayLog? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = TimeTrackingPolicy.dayKey(date)
            return key == log.day ? log : Self.load(day: key)
        }
    }

    /// Publishes the latest totals now (the Flow tab calls this when shown).
    func refreshNow() {
        cachedReport = nil
        publish()
    }

    private var cachedReport: (date: Date, report: TimeWeekReport)?

    /// This week against last week. Cached briefly: it reads two weeks of files.
    func weekReport() -> TimeWeekReport {
        if let cachedReport, Date().timeIntervalSince(cachedReport.date) < 30 { return cachedReport.report }
        let report = TimeTrackingPolicy.weekReport(logs: recentLogs(), endingOn: Date(), work: workCategories)
        cachedReport = (Date(), report)
        return report
    }

    /// Friday from 5 pm, once a week.
    private func checkWeeklyReport(now: Date) {
        guard Defaults[.enableTimeTracking], Defaults[.timeTrackingWeeklyReport], !weeklyReportReady else { return }
        let calendar = Calendar.current
        guard calendar.component(.weekday, from: now) == 6, calendar.component(.hour, from: now) >= 17 else { return }
        let week = "\(calendar.component(.yearForWeekOfYear, from: now))-\(calendar.component(.weekOfYear, from: now))"
        guard Defaults[.timeTrackingLastReportWeek] != week, weekReport().workThisWeek > 0 else { return }
        if FocusQuiet.shared.isQuiet { return }  // try again after the focus block
        Defaults[.timeTrackingLastReportWeek] = week
        withAnimation(.smooth(duration: 0.25)) { weeklyReportReady = true }
        reportWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissWeeklyReport() }
        reportWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func dismissWeeklyReport() {
        reportWork?.cancel()
        if weeklyReportReady { withAnimation(.smooth(duration: 0.25)) { weeklyReportReady = false } }
    }

    // MARK: Export

    /// All saved days as CSV: date, project, hours.
    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NotchFlow hours.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save()
        let logs = Self.allLogs()
        try? TimeTrackingPolicy.csv(logs: logs).write(to: url, atomically: true, encoding: .utf8)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: Self.folder)
        log = TimeDayLog(day: TimeTrackingPolicy.dayKey(Date()))
        publish()
    }

    // MARK: Storage

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/TimeTracking", isDirectory: true)
    }

    private static func file(day: String) -> URL { folder.appendingPathComponent("\(day).json") }

    private func save() {
        lastSave = Date()
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(log) { try? data.write(to: Self.file(day: log.day), options: .atomic) }
    }

    private static func load(day: String) -> TimeDayLog? {
        guard let data = try? Data(contentsOf: file(day: day)) else { return nil }
        return try? JSONDecoder().decode(TimeDayLog.self, from: data)
    }

    private static func allLogs() -> [TimeDayLog] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TimeDayLog.self, from: $0) }
        }
    }

    /// Keeps about four months.
    private static func pruneOldLogs() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()) else { return }
        let oldest = TimeTrackingPolicy.dayKey(cutoff)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "json" && url.deletingPathExtension().lastPathComponent < oldest {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
