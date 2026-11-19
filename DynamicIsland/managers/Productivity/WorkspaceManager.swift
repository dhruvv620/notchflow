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

    private var launches: [AppLaunch] = []
    /// Apps a workspace opened today (not ones that were already running).
    private var launchedToday: Set<String> = []
    private var launchedDay = ""
    private var focusTurnedOn = false
    private var observers: [NSObjectProtocol] = []
    private var started = false

    private init() {
        workspaces = (try? JSONDecoder().decode([Workspace].self, from: Defaults[.workspacesData])) ?? []
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
        workspaces.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) { Defaults[.workspacesData] = data }
    }

    /// What's open right now, as a new workspace: running apps and the front
    /// browser window's tabs.
    func captureCurrentSetup(named name: String = "My setup") async -> Workspace {
        let own = Bundle.main.bundleIdentifier ?? ""
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> WorkspaceApp? in
                guard let id = app.bundleIdentifier, id != own, !WorkspacePolicy.alwaysRunning.contains(id) else { return nil }
                return WorkspaceApp(bundleID: id, name: app.localizedName ?? id)
            }
        var workspace = Workspace(name: name)
        workspace.apps = Array(apps.prefix(8))
        workspace.urls = await frontBrowserTabs()
        return workspace
    }

    private func frontBrowserTabs() async -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let scripts: [(String, String)] = [
            ("com.apple.Safari", #"tell application id "com.apple.Safari" to get URL of every tab of front window"#),
            ("com.google.Chrome", #"tell application id "com.google.Chrome" to get URL of every tab of front window"#),
            ("company.thebrowser.Browser", #"tell application id "company.thebrowser.Browser" to get URL of every tab of front window"#),
            ("com.brave.Browser", #"tell application id "com.brave.Browser" to get URL of every tab of front window"#),
            ("com.microsoft.edgemac", #"tell application id "com.microsoft.edgemac" to get URL of every tab of front window"#),
        ]
        for (id, script) in scripts where running.contains(id) {
            guard let result = try? await AppleScriptHelper.execute(script) else { continue }
            var urls: [String] = []
            if result.numberOfItems > 0 {
                for index in 1...result.numberOfItems {
                    if let url = result.atIndex(index)?.stringValue, url.hasPrefix("http") { urls.append(url) }
                }
            } else if let url = result.stringValue, url.hasPrefix("http") {
                urls.append(url)
            }
            if !urls.isEmpty { return Array(urls.prefix(10)) }
        }
        return []
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
            if !running.contains(app.bundleID) { launchedToday.insert(app.bundleID) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            if app.bundleID == opener, !workspace.folders.isEmpty {
                let folders = workspace.folders.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                NSWorkspace.shared.open(folders, withApplicationAt: url, configuration: configuration)
            } else {
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
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
        if workspace.layout != .none {
            // Apps take a moment to open their windows; arrange twice.
            for delay in [1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.arrange(workspace) }
            }
        }
        // Bring the first app to the front at the end.
        if let first = workspace.apps.first,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: first.bundleID).first {
            app.activate()
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
    private func arrange(_ workspace: Workspace) {
        guard AXIsProcessTrusted(), let screen = NSScreen.main else { return }
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
