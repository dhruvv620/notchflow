// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let enableWorkspaces = Key<Bool>("enableWorkspaces", default: true)
    static let workspacesData = Key<Data>("workspacesData", default: Data())
    /// Recent app launches, for suggesting workspaces (on this Mac only).
    static let workspaceLaunchLog = Key<Data>("workspaceLaunchLog", default: Data())
    /// Suggest a workspace for apps you keep opening together.
    static let workspaceSuggestions = Key<Bool>("workspaceSuggestions", default: true)
    static let workspaceDismissedSuggestions = Key<[String]>("workspaceDismissedSuggestions", default: [])
    /// "Done for the day" quits the apps workspaces opened today.
    static let workspaceDoneQuitsApps = Key<Bool>("workspaceDoneQuitsApps", default: true)
    /// Setups saved from the screen were cut down to their windows once.
    static let workspacesWindowsOnly = Key<Bool>("workspacesWindowsOnly", default: false)
}

/// Saved setups you switch to from the Flow tab: apps, pages, folders, a
/// terminal, window layout, Focus, music and a Pomodoro, in one tap.
@MainActor
final class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var suggestion: WorkspaceSuggestion?
    /// The workspace opened last, until Done for the day.
    @Published private(set) var activeID: UUID?
    /// Set by Done for the day, to show the day's summary.
    @Published var showDaySummary = false
    @Published private(set) var lastMessage: String?

    func clearMessage() { lastMessage = nil }
    /// The workspace just deleted, for Undo (cleared after a few seconds).
    @Published private(set) var recentlyDeleted: (workspace: Workspace, index: Int)?
    private var undoWork: DispatchWorkItem?

    private var launches: [AppLaunch] = []
    /// Apps a workspace opened today (not ones that were already running).
    private var launchedToday: Set<String> = []
    private var launchedDay = ""
    private var focusTurnedOn = false
    private var observers: [NSObjectProtocol] = []
    private var started = false

    private init() {
        workspaces = (try? JSONDecoder().decode([Workspace].self, from: Defaults[.workspacesData])) ?? []
        // Setups are windows only now: saved web pages (opened again every
        // time, as duplicate tabs) and apps without a window are dropped once.
        if !Defaults[.workspacesWindowsOnly] {
            workspaces = workspaces.map(WorkspacePolicy.windowsOnlySetup)
            if let data = try? JSONEncoder().encode(workspaces) { Defaults[.workspacesData] = data }
            Defaults[.workspacesWindowsOnly] = true
        }
        launches = (try? JSONDecoder().decode([AppLaunch].self, from: Defaults[.workspaceLaunchLog])) ?? []
    }

    func start() {
        guard !started else { return }
        started = true
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let id = app?.bundleIdentifier, name = app?.localizedName, regular = app?.activationPolicy == .regular
                MainActor.assumeIsolated { if regular, let id { self?.recordLaunch(id, name: name ?? id) } }
            })
        refreshSuggestion()
    }

    // MARK: Editing

    func save(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
        persist()
        refreshSuggestion()
    }

    func delete(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let removed = workspaces[index]
        withAnimation(.smooth(duration: 0.25)) {
            workspaces.remove(at: index)
            recentlyDeleted = (removed, index)
        }
        if activeID == id { activeID = nil }
        persist()
        refreshSuggestion()
        undoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth(duration: 0.25)) { self?.recentlyDeleted = nil }
        }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func undoDelete() {
        guard let deleted = recentlyDeleted else { return }
        undoWork?.cancel()
        withAnimation(.smooth(duration: 0.25)) {
            workspaces.insert(deleted.workspace, at: min(deleted.index, workspaces.count))
            recentlyDeleted = nil
        }
        persist()
        refreshSuggestion()
    }

    func move(from source: IndexSet, to destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) { Defaults[.workspacesData] = data }
    }

    /// The windows on screen right now, as a new setup: each visible window's
    /// app, position, size and screen. Not apps without a window, not
    /// minimized windows, not browser tabs.
    func captureCurrentSetup(named name: String = "My setup") async -> Workspace {
        var workspace = Workspace(name: name)
        guard AXIsProcessTrusted() else {
            lastMessage = "Allow NotchFlow in System Settings › Privacy & Security › Accessibility to save window setups."
            return workspace
        }
        workspace.apps = WorkspacePolicy.windowsOnly(Self.currentApps())
        workspace.layout = .restore
        if workspace.apps.isEmpty { lastMessage = "No windows on screen to save." }
        return workspace
    }

    /// Running apps, with their windows' places when Accessibility is allowed.
    private static func currentApps() -> [WorkspaceApp] {
        let own = Bundle.main.bundleIdentifier ?? ""
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden }
            .compactMap { app -> WorkspaceApp? in
                guard let id = app.bundleIdentifier, id != own, !WorkspacePolicy.alwaysRunning.contains(id) else { return nil }
                // Only this desktop's windows: a setup is the desktop you made it on.
                let windows = windowsOnThisDesktop(of: app).compactMap { window -> WorkspaceWindow? in
                    guard let frame = frame(of: window) else { return nil }
                    return WorkspaceWindow(frame: frame, title: title(of: window))
                }
                return WorkspaceApp(bundleID: id, name: app.localizedName ?? id, windows: AXIsProcessTrusted() ? windows : nil)
            }
        return Array(apps.prefix(16))
    }

    /// Replaces a workspace's apps, window places and pages with what's open
    /// now, keeping its name and options.
    func updateFromCurrent(_ id: UUID) async {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        guard AXIsProcessTrusted() else {
            lastMessage = "Allow NotchFlow in System Settings › Privacy & Security › Accessibility to save window setups."
            return
        }
        let apps = WorkspacePolicy.windowsOnly(Self.currentApps())
        guard !apps.isEmpty else {
            lastMessage = "No windows on screen to save."
            return
        }
        var workspace = workspaces[index]
        workspace.apps = apps
        workspace.urls = []
        workspace.layout = .restore
        save(workspace)
        lastMessage = "Updated \(workspace.name) to the current layout."
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = trimmed
        persist()
    }

    // MARK: Opening

    func open(_ workspace: Workspace) {
        resetDayIfNeeded()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if workspace.hideOtherApps {
            let keep = Set(workspace.apps.map(\.bundleID)).union([Bundle.main.bundleIdentifier ?? ""])
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                if let id = app.bundleIdentifier, !keep.contains(id) { app.hide() }
            }
        }

        // Apps (folders open in the workspace's editor, when it has one).
        let opener = WorkspacePolicy.folderOpener(for: workspace)
        for app in workspace.apps {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { continue }
            // A window setup leaves running apps alone (opening one could switch
            // to the desktop where its window is); missing windows are handled below.
            if workspace.layout == .restore && running.contains(app.bundleID) { continue }
            if !running.contains(app.bundleID) { launchedToday.insert(app.bundleID) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            if app.bundleID == opener, !workspace.folders.isEmpty {
                let folders = workspace.folders.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                NSWorkspace.shared.open(folders, withApplicationAt: url, configuration: configuration)
            } else {
                launch(app, at: url, configuration: configuration)
            }
        }
        if opener == nil {
            for folder in workspace.folders {
                NSWorkspace.shared.open(URL(fileURLWithPath: (folder as NSString).expandingTildeInPath))
            }
        }
        for address in workspace.urls {
            if let url = WorkspacePolicy.normalizedURL(address) { NSWorkspace.shared.open(url) }
        }
        if !workspace.terminalFolder.isEmpty {
            let path = (workspace.terminalFolder as NSString).expandingTildeInPath
            let terminal = AgentHookPolicy.TerminalApp(rawValue: Defaults[.agentTerminalApp]) ?? .terminal
            if !running.contains(terminal.bundleID) { launchedToday.insert(terminal.bundleID) }
            let script = AgentHookPolicy.appleScript(running: "cd " + AgentHookPolicy.shellQuoted(path), in: terminal)
            Task { try? await AppleScriptHelper.executeVoid(script) }
        }

        if workspace.turnOnFocus {
            FocusHistory.runShortcut(named: Defaults[.pomodoroFocusOnShortcut])
            focusTurnedOn = true
        }
        if workspace.playMusic { startMusic(playlist: workspace.playlist) }
        if workspace.startPomodoro, !TimerModesManager.shared.pomodoro.isActive {
            TimerModesManager.shared.startPomodoro(configuration: Self.pomodoroConfiguration())
        }
        let session = UUID()
        if workspace.layout == .restore {
            restoreSession = (session, [:], [])
            followRestore(workspace, session: session, alreadyRunning: Set(workspace.apps.map(\.bundleID)).intersection(running))
        } else if workspace.layout != .none {
            // Apps take a moment to open their windows; arrange a few times
            // (more for "exactly as saved", which waits for every window).
            for delay in [1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.arrange(workspace, session: session) }
            }
        }
        // Bring the first app to the front at the end, unless that would switch
        // to another desktop (its windows are elsewhere); window setups stay on
        // the desktop you're on.
        if workspace.layout != .restore, let first = workspace.apps.first,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: first.bundleID).first,
           !Self.onScreenWindowFrames(of: app.processIdentifier).isEmpty {
            app.activate()
        }
        // Switching desktops while the windows are being placed stops it there.
        if workspace.layout == .restore {
            spaceWatch.map(NSWorkspace.shared.notificationCenter.removeObserver)
            spaceWatch = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.restoreSession?.id == session else { return }
                    self.restoreSession = nil
                }
            }
        }
        withAnimation(.smooth(duration: 0.25)) { activeID = workspace.id; showDaySummary = false }
        lastMessage = "Opened \(workspace.name)."
    }

    private func startMusic(playlist: String) {
        let name = playlist.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"Music\" to play playlist \"" + escaped + "\""
            Task { try? await AppleScriptHelper.executeVoid(script) }
        } else {
            MusicManager.shared.play()
        }
    }

    private static func pomodoroConfiguration() -> PomodoroConfiguration {
        let defaults = UserDefaults.standard
        func value(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }
        let sessions = defaults.object(forKey: "notchflowPomodoroSessionCount") == nil ? 4 : defaults.integer(forKey: "notchflowPomodoroSessionCount")
        return PomodoroConfiguration(focusDuration: value("notchflowPomodoroFocusMinutes", 25) * 60,
                                     shortBreakDuration: value("notchflowPomodoroShortBreakMinutes", 5) * 60,
                                     longBreakDuration: value("notchflowPomodoroLongBreakMinutes", 15) * 60,
                                     sessionsBeforeLongBreak: sessions)
    }

    /// Places the first apps' front windows side by side (needs Accessibility).
    private func arrange(_ workspace: Workspace, session: UUID) {
        guard AXIsProcessTrusted(), let screen = NSScreen.main else { return }
        if workspace.layout == .restore {
            // Done once every window is in place; a newer open of a setup takes over.
            guard !isRestoreComplete(workspace, session: session) else { return }
            restoreWindows(workspace, session: session)
            return
        }
        // Accessibility uses a top-left origin on the main display.
        let full = NSScreen.screens.first?.frame ?? screen.frame
        let visible = screen.visibleFrame
        let topLeft = CGRect(x: visible.minX, y: full.maxY - visible.maxY, width: visible.width, height: visible.height)
        let ids = workspace.apps.map(\.bundleID)
        let frames = WorkspacePolicy.frames(for: workspace.layout, visible: topLeft, count: ids.count)
        for (id, frame) in zip(ids, frames) {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var window: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success
                    || AXUIElementCopyAttributeValue(element, kAXMainWindowAttribute as CFString, &window) == .success,
                  let window else { continue }
            var origin = frame.origin, size = frame.size
            if let position = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, position)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, sizeValue)
            }
        }
    }

    /// Starts an app the setup needs. If it doesn't start in the background
    /// (some apps refuse, or the request is lost), it's asked again in the
    /// usual way, and you're told when it can't be opened at all.
    private func launch(_ app: WorkspaceApp, at url: URL, configuration: NSWorkspace.OpenConfiguration) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { running, error in
            guard running == nil || error != nil else { return }
            DispatchQueue.main.async {
                let retry = NSWorkspace.OpenConfiguration()
                retry.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: retry) { running, error in
                    guard running == nil, let error else { return }
                    DispatchQueue.main.async { [weak self] in
                        self?.lastMessage = "\(app.name) didn't open: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private var restoreTask: Task<Void, Never>?

    /// Follows a window setup as it opens, every half second for up to half
    /// a minute: each window is put in place as soon as it appears, an app
    /// that hasn't started is started again, and once an app has started
    /// (or right away, when it was already running) the windows it didn't
    /// open itself are opened: a new window in a browser, or the app's own
    /// reopen. Stops when every window is in place.
    private func followRestore(_ workspace: Workspace, session: UUID, alreadyRunning: Set<String>) {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            var startedAt: [String: Date] = [:]
            var opened = Set<String>()
            var relaunched = Set<String>()
            for step in 1...60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled, self.restoreSession?.id == session else { return }
                self.arrange(workspace, session: session)
                if self.isRestoreComplete(workspace, session: session) { return }
                let elapsed = Double(step) * 0.5
                for app in workspace.apps where !opened.contains(app.bundleID) {
                    guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else {
                        // Not running yet after a few seconds: ask once more.
                        if elapsed >= 4, relaunched.insert(app.bundleID).inserted,
                           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                            let configuration = NSWorkspace.OpenConfiguration()
                            configuration.activates = false
                            self.launch(app, at: url, configuration: configuration)
                        }
                        continue
                    }
                    // A just-started app opens its own windows first (a browser
                    // restoring its last windows); give it a moment.
                    let wait: TimeInterval = alreadyRunning.contains(app.bundleID) ? 0 : 2.5
                    guard running.isFinishedLaunching else { continue }
                    let since = startedAt[app.bundleID] ?? Date()
                    startedAt[app.bundleID] = since
                    guard Date().timeIntervalSince(since) >= wait else { continue }
                    opened.insert(app.bundleID)
                    self.openMissingWindows(workspace, only: [app.bundleID], session: session)
                }
            }
        }
    }

    /// Opens windows the setup saved but that aren't open: a new window in a
    /// browser, or the app's own reopen (as clicking its Dock icon does).
    private func openMissingWindows(_ workspace: Workspace, only bundleIDs: Set<String>, session: UUID) {
        guard AXIsProcessTrusted(), restoreSession?.id == session else { return }
        for app in workspace.apps where bundleIDs.contains(app.bundleID) {
            // Already placed (and maybe minimized or closed by you since): leave it.
            let saved = (app.windows?.count ?? 0) - (restoreSession?.placed[app.bundleID]?.count ?? 0)
            guard saved > 0,
                  let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else { continue }
            let placedWindows = restoreSession?.windows ?? []
            let unplaced = Self.windowsOnThisDesktop(of: running)
                .filter { window in !placedWindows.contains { CFEqual($0, window) } }
            let missing = WorkspacePolicy.windowsToOpen(saved: saved, open: unplaced.count)
            guard missing > 0 else { continue }
            if let script = WorkspacePolicy.newWindowScript(for: app.bundleID) {
                // A new browser window opens on the desktop you're on. If the
                // browser can't be told (Automation not allowed), its reopen does it.
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
                Task { @MainActor [weak self] in
                    for _ in 0..<missing {
                        do {
                            try await AppleScriptHelper.executeVoid(script)
                        } catch {
                            if Self.windowCountOnAnyDesktop(of: running.processIdentifier) == 0, let url {
                                let configuration = NSWorkspace.OpenConfiguration()
                                configuration.activates = true
                                NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
                            } else {
                                self?.lastMessage = "Allow NotchFlow to control \(app.name) (System Settings › Privacy & Security › Automation) so setups can open its windows."
                            }
                            break
                        }
                    }
                }
            } else if Self.windowCountOnAnyDesktop(of: running.processIdentifier) == 0,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                // No window anywhere: reopening it puts one here.
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } else {
                // Its window is on another desktop: left there (switching to it
                // would take you away from this one).
                lastMessage = "\(app.name)'s window is on another desktop, so it was left there."
            }
        }
    }

    /// Puts every saved window back where it was, as far as the app has
    /// opened them (matched by title, then in order).
    /// The setup being opened: which saved windows are already in place, and
    /// the windows that were put there. Each window is placed once; later
    /// passes only look for windows that hadn't appeared yet, so a window you
    /// minimize or move right after isn't pulled back.
    private var restoreSession: (id: UUID, placed: [String: Set<Int>], windows: [AXUIElement])?
    private var spaceWatch: NSObjectProtocol?

    /// The frames of an app's windows on the desktop you're looking at (Window
    /// Server's on-screen list holds only the current desktop's windows).
    private static func onScreenWindowFrames(of pid: pid_t) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }

    /// How many normal windows an app has on any desktop.
    private static func windowCountOnAnyDesktop(of pid: pid_t) -> Int {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return 0 }
        return list.filter { info in
            (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && ((info[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?.height ?? 0) > 40
        }.count
    }

    /// The app's normal windows on the desktop you're on: never one on
    /// another desktop, so a setup made on Desktop 2 leaves Desktop 1 alone.
    private static func windowsOnThisDesktop(of app: NSRunningApplication) -> [AXUIElement] {
        let visible = onScreenWindowFrames(of: app.processIdentifier)
        return standardWindows(of: app, includeMinimized: false).filter { window in
            guard let frame = frame(of: window) else { return false }
            return visible.contains { abs($0.minX - frame.minX) < 3 && abs($0.minY - frame.minY) < 3
                && abs($0.width - frame.width) < 3 && abs($0.height - frame.height) < 3 }
        }
    }

    private func restoreWindows(_ workspace: Workspace, session: UUID) {
        guard var current = restoreSession, current.id == session else { return }
        let screens = Self.screensInAccessibilityCoordinates()
        for app in workspace.apps {
            guard let saved = app.windows, !saved.isEmpty,
                  let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else { continue }
            let done = current.placed[app.bundleID] ?? []
            let waiting = saved.indices.filter { !done.contains($0) }
            guard !waiting.isEmpty else { continue }
            if running.isHidden { running.unhide() }
            let windows = Self.windowsOnThisDesktop(of: running)
                .filter { window in !current.windows.contains { CFEqual($0, window) } }
            guard !windows.isEmpty else { continue }
            let titles = windows.map { Self.title(of: $0) ?? "" }
            for pair in WorkspacePolicy.matchWindows(saved: waiting.map { saved[$0] }, titles: titles) {
                let window = windows[pair.window]
                Self.move(window, to: WorkspacePolicy.fitted(saved[waiting[pair.saved]].frame, screens: screens))
                current.placed[app.bundleID, default: []].insert(waiting[pair.saved])
                current.windows.append(window)
            }
        }
        restoreSession = current
    }

    /// Whether every saved window of the setup being opened is in place.
    private func isRestoreComplete(_ workspace: Workspace, session: UUID) -> Bool {
        guard let current = restoreSession, current.id == session else { return true }
        return workspace.apps.allSatisfy { app in (current.placed[app.bundleID]?.count ?? 0) >= (app.windows?.count ?? 0) }
    }

    // MARK: Accessibility helpers

    /// The app's ordinary windows (not panels, sheets or tool palettes).
    private static func standardWindows(of app: NSRunningApplication, includeMinimized: Bool = false) -> [AXUIElement] {
        guard AXIsProcessTrusted() else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            guard (subrole as? String) == (kAXStandardWindowSubrole as String) else { return false }
            if includeMinimized { return true }
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            return (minimized as? Bool) != true
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Moves, resizes, then moves again (some apps limit size by position).
    private static func move(_ window: AXUIElement, to frame: CGRect) {
        var origin = frame.origin, size = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    /// Each screen, in Accessibility coordinates (top left of the main
    /// display is 0,0; y grows downward). The whole screen, so a window that
    /// reaches under the Dock keeps its exact size.
    private static func screensInAccessibilityCoordinates() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.map { screen in
            let area = screen.frame
            return CGRect(x: area.minX, y: primary.frame.maxY - area.maxY, width: area.width, height: area.height)
        }
    }

    // MARK: Done for the day

    /// Quits what workspaces opened today, turns Focus off, ends the
    /// Pomodoro and shows the day's summary.
    func doneForTheDay() {
        resetDayIfNeeded()
        if Defaults[.workspaceDoneQuitsApps] {
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            let quit = WorkspacePolicy.appsToQuit(launchedByWorkspaces: launchedToday, running: running,
                                                  ownBundleID: Bundle.main.bundleIdentifier ?? "")
            for id in quit {
                // A normal quit: apps still ask to save unsaved work.
                NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
            }
            launchedToday.subtract(quit)
        }
        if focusTurnedOn {
            FocusHistory.runShortcut(named: Defaults[.pomodoroFocusOffShortcut])
            focusTurnedOn = false
        }
        if TimerModesManager.shared.pomodoro.isActive { TimerModesManager.shared.stopPomodoro() }
        withAnimation(.smooth(duration: 0.25)) {
            activeID = nil
            showDaySummary = true
        }
        lastMessage = "Done for the day. Nice work."
    }

    private func resetDayIfNeeded() {
        let today = TimeTrackingPolicy.dayKey(Date())
        if launchedDay != today { launchedDay = today; launchedToday = [] }
    }

    // MARK: Suggestions

    private func recordLaunch(_ bundleID: String, name: String) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        launches = WorkspacePolicy.trimmed(launches + [AppLaunch(bundleID: bundleID, name: name, date: Date())], now: Date())
        if let data = try? JSONEncoder().encode(launches) { Defaults[.workspaceLaunchLog] = data }
        refreshSuggestion()
    }

    func refreshSuggestion() {
        guard Defaults[.enableWorkspaces], Defaults[.workspaceSuggestions] else { suggestion = nil; return }
        suggestion = WorkspacePolicy.suggestion(launches: launches, existing: workspaces.map { Set($0.apps.map(\.bundleID)) },
                                                dismissed: Set(Defaults[.workspaceDismissedSuggestions]), now: Date(),
                                                ownBundleID: Bundle.main.bundleIdentifier ?? "")
    }

    func acceptSuggestion() {
        guard let suggestion else { return }
        var workspace = Workspace(name: suggestion.name)
        workspace.apps = suggestion.apps
        save(workspace)
        lastMessage = "Saved \(suggestion.name). Edit it in Settings > Productivity."
    }

    func dismissSuggestion() {
        guard let suggestion else { return }
        Defaults[.workspaceDismissedSuggestions].append(suggestion.key)
        refreshSuggestion()
    }

    func clearLaunchHistory() {
        launches = []
        Defaults[.workspaceLaunchLog] = Data()
        refreshSuggestion()
    }
}
