// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import Foundation

extension Defaults.Keys {
    /// Suggest your best focus hours (from time tracking) and block them.
    static let orbitFocusPlan = Key<Bool>("orbitFocusPlan", default: false)
    /// The scene to run when a focus block starts (OrbitScene id, empty: none).
    static let orbitFocusScene = Key<String>("orbitFocusScene", default: "")
    /// Notice jumping between many apps, and offer focus.
    static let orbitScatter = Key<Bool>("orbitScatter", default: false)
    /// Spot renewals and bills in messages and put them in Loops.
    static let orbitBillWatch = Key<Bool>("orbitBillWatch", default: false)
    /// Shutdown steps (each can be left out).
    static let orbitShutdownWorkspace = Key<Bool>("orbitShutdownWorkspace", default: true)
    static let orbitShutdownBackup = Key<Bool>("orbitShutdownBackup", default: true)
    static let orbitShutdownQuiet = Key<Bool>("orbitShutdownQuiet", default: true)
}

/// Orbit's day rhythm. Each part runs only while its switch (and Orbit) is on:
/// the scattered check listens for app switches, bill watching reads new
/// notifications, a focus block is one timer. Off: nothing at all.
@MainActor
final class OrbitRhythm: ObservableObject {
    static let shared = OrbitRhythm()

    /// Jumping between many apps right now (apps in the last 10 minutes).
    @Published private(set) var scatteredApps: Int?
    @Published private(set) var shutdownReport: [String] = []
    @Published private(set) var isShuttingDown = false

    private var isActive = false
    private var switchObserver: NSObjectProtocol?
    private var switches: [OrbitRhythmPolicy.Switch] = []
    private var lastScatterShown = Date.distantPast
    private var scatterClear: Task<Void, Never>?
    private var billWatch: AnyCancellable?
    private var seenNotifications = Set<String>()
    private var focusTimer: Timer?
    private var cachedWindow: (day: String, window: OrbitRhythmPolicy.FocusWindow?)?

    private init() {}

    /// Called by Orbit when its switches change.
    func setActive(_ active: Bool) {
        isActive = active
        let scatter = active && Defaults[.orbitScatter]
        if scatter && switchObserver == nil {
            switchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                Task { @MainActor in OrbitRhythm.shared.appSwitched(app) }
            }
        } else if !scatter, let observer = switchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            switchObserver = nil
            switches = []
            scatteredApps = nil
        }
        let bills = active && Defaults[.orbitBillWatch]
        if bills && billWatch == nil {
            seenNotifications = Set(NotificationHub.shared.items.map(\.id))
            billWatch = NotificationHub.shared.$items
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
                .sink { [weak self] in self?.notificationsChanged($0) }
        } else if !bills {
            billWatch = nil
            seenNotifications = []
        }
        if active && Defaults[.orbitFocusPlan] { scheduleFocusBlock() } else { focusTimer?.invalidate(); focusTimer = nil }
        if !active { cachedWindow = nil; shutdownReport = [] }
    }

    // MARK: Scattered

    private func appSwitched(_ bundleID: String?) {
        guard isActive, let bundleID, bundleID != Bundle.main.bundleIdentifier, bundleID != "com.apple.loginwindow" else { return }
        let now = Date()
        switches = OrbitRhythmPolicy.trimmed(switches + [.init(date: now, app: bundleID)], now: now)
        let (count, apps) = OrbitRhythmPolicy.scatter(switches, now: now)
        guard OrbitRhythmPolicy.isScattered(switches: count, apps: apps), scatteredApps == nil,
              !FocusQuiet.shared.isQuiet, now.timeIntervalSince(lastScatterShown) > 30 * 60 else { return }
        lastScatterShown = now
        scatteredApps = apps
        scatterClear?.cancel()
        scatterClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.scatteredApps = nil
        }
    }

    /// From the Scattered card: 25 minutes of quiet on one thing.
    func focusNow(minutes: Int = 25) {
        scatteredApps = nil
        switches = []
        FocusQuiet.shared.startManual(minutes: minutes)
    }

    func dismissScatter() { scatteredApps = nil }

    // MARK: Best focus hours

    /// Your best two hours, from the last two weeks of time tracking (cached per day).
    var focusWindow: OrbitRhythmPolicy.FocusWindow? {
        let today = OrbitPolicy.dayKey(Date())
        if let cachedWindow, cachedWindow.day == today { return cachedWindow.window }
        let window = Defaults[.timeTrackingEnabled]
            ? OrbitRhythmPolicy.bestFocusWindow(logs: TimeTracker.shared.recentLogs()) : nil
        cachedWindow = (today, window)
        return window
    }

    /// Today's block ("10|12"), if one is set.
    var blockToday: (start: Int, end: Int)? {
        let parts = Orbit.shared.state.focusBlock.split(separator: "|")
        guard parts.count == 3, String(parts[0]) == OrbitPolicy.dayKey(Date()),
              let start = Int(parts[1]), let end = Int(parts[2]) else { return nil }
        return (start, end)
    }

    func block(_ window: OrbitRhythmPolicy.FocusWindow) {
        Orbit.shared.setFocusBlock("\(OrbitPolicy.dayKey(Date()))|\(window.start)|\(window.end)")
        scheduleFocusBlock()
        objectWillChange.send()
    }

    func cancelBlock() {
        Orbit.shared.setFocusBlock("")
        focusTimer?.invalidate()
        focusTimer = nil
        objectWillChange.send()
    }

    /// One timer for the block's start; if it's already under way, start now.
    private func scheduleFocusBlock() {
        focusTimer?.invalidate()
        focusTimer = nil
        guard isActive, Defaults[.orbitFocusPlan], let block = blockToday else { return }
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(bySettingHour: block.start, minute: 0, second: 0, of: now),
              let end = calendar.date(bySettingHour: block.end, minute: 0, second: 0, of: now), end > now else { return }
        if start <= now {
            beginFocus(until: end)
            return
        }
        let timer = Timer(fire: start, interval: 0, repeats: false) { _ in
            Task { @MainActor in OrbitRhythm.shared.beginFocus(until: end) }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer
    }

    private func beginFocus(until end: Date) {
        guard isActive, Defaults[.orbitFocusPlan], !FocusQuiet.shared.isQuiet else { return }
        let minutes = max(5, Int(end.timeIntervalSinceNow / 60))
        FocusQuiet.shared.startManual(minutes: minutes)
        if let id = UUID(uuidString: Defaults[.orbitFocusScene]),
           let scene = Orbit.shared.state.scenes.first(where: { $0.id == id }) {
            Orbit.shared.run(scene)
        }
        NotificationHub.shared.post(id: "orbit-focus-\(OrbitPolicy.dayKey(Date()))", appName: "Orbit",
                                    title: "Deep work until \(end.formatted(date: .omitted, time: .shortened))",
                                    body: "Your best hours. Notifications are held until then.")
    }

    // MARK: Bills

    private func notificationsChanged(_ items: [NotchNotification]) {
        guard isActive, Defaults[.orbitBillWatch] else { return }
        let fresh = items.filter { !seenNotifications.contains($0.id) }
        seenNotifications = Set(items.map(\.id))
        for item in fresh {
            let text = [item.title, item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
            guard OrbitRhythmPolicy.isBillMessage(text) else { continue }
            let due = Self.firstDate(in: text, after: item.date)
            let service = OrbitRhythmPolicy.service(in: text, sender: item.title, app: item.appName)
            let bill = OrbitBill(id: OrbitRhythmPolicy.billID(service: service, due: due), service: service,
                                 amount: OrbitRhythmPolicy.amount(in: text), due: due, source: item.appName,
                                 seen: item.date, snippet: OrbitPolicy.clip(text, to: 140))
            Orbit.shared.addBill(bill)
        }
    }

    /// The first date mentioned that isn't in the past ("on Dec 3", "tomorrow").
    static func firstDate(in text: String, after reference: Date) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.date).first { $0 > reference.addingTimeInterval(-86_400) }
    }

    // MARK: Shutdown

    /// Folders of Orbit projects that are git repositories.
    private var projectRoots: [String] {
        Orbit.shared.state.projects.values.compactMap(\.root)
            .filter { FileManager.default.fileExists(atPath: ($0 as NSString).appendingPathComponent(".git")) }
    }

    /// Ends the day: tomorrow's top three, a saved workspace, unsaved code
    /// backed up to a branch (without touching your files), quiet until the morning.
    func shutDown() async {
        guard isActive, !isShuttingDown else { return }
        isShuttingDown = true
        defer { isShuttingDown = false }
        var report: [String] = []
        let now = Date()

        let top = OrbitRhythmPolicy.tomorrowTop(Orbit.shared.loops(), now: now)
        Orbit.shared.setTomorrowTop(top.map(\.title))
        report.append(top.isEmpty ? "Nothing open for tomorrow." : "Tomorrow: " + top.map(\.title).joined(separator: " · "))

        if Defaults[.orbitShutdownWorkspace], Defaults[.enableWorkspaces] {
            let name = "End of day \(now.formatted(date: .abbreviated, time: .omitted))"
            let workspace = await WorkspaceManager.shared.captureCurrentSetup(named: name)
            WorkspaceManager.shared.save(workspace)
            report.append("Saved your windows as \u{201C}\(name)\u{201D}.")
        }

        if Defaults[.orbitShutdownBackup] {
            let branch = OrbitRhythmPolicy.backupBranch(day: OrbitPolicy.dayKey(now))
            for root in projectRoots {
                let line = await Self.backUp(root: root, branch: branch)
                if let line { report.append(line) }
            }
        }

        if Defaults[.orbitShutdownQuiet] {
            FocusQuiet.shared.startManual(minutes: OrbitRhythmPolicy.minutesUntilMorning(now: now, hour: Defaults[.orbitBriefHour]))
            report.append("Quiet until \(OrbitRhythmPolicy.hourText(Defaults[.orbitBriefHour])) tomorrow.")
        }

        WorkspaceManager.shared.doneForTheDay()
        shutdownReport = report
    }

    /// Saves uncommitted changes as a commit on `branch` (pushed when there's a
    /// remote) using `git stash create`, which changes nothing in your folder.
    private static func backUp(root: String, branch: String) async -> String? {
        let name = (root as NSString).lastPathComponent
        let status = await git(["status", "--porcelain", "--untracked-files=no"], in: root)
        guard status.status == 0, !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let stash = await git(["stash", "create", "NotchFlow end-of-day backup"], in: root)
        let sha = stash.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stash.status == 0, !sha.isEmpty else { return "\(name): couldn't back up changes." }
        let remote = await git(["remote"], in: root)
        if remote.output.split(whereSeparator: \.isNewline).contains("origin") {
            let pushed = await git(["push", "-q", "origin", "\(sha):refs/heads/\(branch)", "--force"], in: root)
            if pushed.status == 0 { return "\(name): changes backed up to \(branch) on GitHub." }
        }
        let local = await git(["branch", "-f", branch, sha], in: root)
        return local.status == 0 ? "\(name): changes backed up to branch \(branch) (on this Mac)." : "\(name): couldn't back up changes."
    }

    private static func git(_ arguments: [String], in directory: String) async -> (status: Int32, output: String) {
        await Task.detached(priority: .utility) { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Repositories with unsaved (uncommitted) changes, for the shutdown preview.
    func reposWithChanges() async -> [String] {
        var found: [String] = []
        for root in projectRoots {
            let status = await Self.git(["status", "--porcelain", "--untracked-files=no"], in: root)
            if status.status == 0, !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append((root as NSString).lastPathComponent)
            }
        }
        return found
    }

    func clearReport() { shutdownReport = [] }
}
