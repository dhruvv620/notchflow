// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Productivity: time tracking, the promise keeper and workspaces.
struct ProductivitySettings: View {
    @ObservedObject private var tracker = TimeTracker.shared
    @ObservedObject private var keeper = PromiseKeeper.shared
    @ObservedObject private var workspaces = WorkspaceManager.shared
    @Default(.timeTrackingEnabled) private var trackingEnabled
    @Default(.timeTrackingGoalHours) private var goalHours
    @Default(.timeTrackingWorkCategories) private var workCategories
    @Default(.timeTrackingProjects) private var extraProjects
    @Default(.enablePromiseKeeper) private var promisesEnabled
    @Default(.promiseNudgeMinutes) private var nudgeMinutes
    @Default(.promiseUseAI) private var useAI
    @State private var previewsAllowed = CGPreflightScreenCaptureAccess()
    @Default(.enableWorkspaces) private var workspacesEnabled
    @State private var editing: Workspace?
    @State private var confirmClearTime = false

    // SettingsTab is private to SettingsView.swift; ids follow its "<tab>-<title>" form.
    private func highlightID(_ title: String) -> String { "productivity-\(title)" }

    var body: some View {
        Form {
            timeSection
            promiseSection
            workspaceSection
            stashSection
        }
        .sheet(item: $editing) { workspace in
            WorkspaceEditor(workspace: workspace) { saved in
                if let saved { workspaces.save(saved) }
                editing = nil
            }
        }
        .alert("Erase all tracked time?", isPresented: $confirmClearTime) {
            Button("Erase", role: .destructive) { tracker.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every day NotchFlow has tracked. It can't be undone.")
        }
    }

    // MARK: Time tracking

    private var timeSection: some View {
        Section {
            Defaults.Toggle(key: .timeTrackingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track where my time goes")
                    Text("NotchFlow notes the app in front every few seconds (and the website, for browsers) and adds up your day by category and project. Idle time and a locked screen don't count. Everything stays on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Track where my time goes"))
            if trackingEnabled {
                Defaults.Toggle(key: .timeTrackingSites) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tell websites apart")
                        Text("Reads the address of the front browser tab (Safari, Chrome, Arc, Brave, Edge). macOS asks once per browser.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Tell websites apart"))
                Stepper(value: $goalHours, in: 0.5...12, step: 0.5) {
                    Text("Daily work goal: \(goalHours.formatted(.number.precision(.fractionLength(0...1)))) hours")
                }
                .settingsHighlight(id: highlightID("Daily work goal"))
                DisclosureGroup("Counts as work: \(workSummary)") {
                    ForEach(TimeCategory.allCases, id: \.self) { category in
                        Toggle(category.title, isOn: Binding(
                            get: { TimeTrackingPolicy.workCategories(from: workCategories).contains(category) },
                            set: { on in
                                var set = TimeTrackingPolicy.workCategories(from: workCategories)
                                if on { set.insert(category) } else { set.remove(category) }
                                workCategories = set.map(\.rawValue).sorted()
                            }))
                    }
                }
                Defaults.Toggle(key: .timeTrackingShowRing) { Text("Show the work ring under the closed notch") }
                    .settingsHighlight(id: highlightID("Show the work ring under the closed notch"))
                Defaults.Toggle(key: .timeTrackingWeeklyReport) { Text("Weekly report on Friday afternoon") }
                    .settingsHighlight(id: highlightID("Weekly report on Friday afternoon"))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Project names", text: $extraProjects, prompt: Text("acme-site, thesis, client-x"))
                    Text("Projects are found in window titles of editors, terminals and Xcode, and from your AI agent sessions. Add other names here, comma separated, to recognize them anywhere (a Figma file, a Google Doc).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .settingsHighlight(id: highlightID("Project names"))
                HStack {
                    Button("Export hours (CSV)…") { tracker.exportCSV() }
                    Spacer()
                    Button("Erase tracked time…", role: .destructive) { confirmClearTime = true }
                }
            }
        } header: {
            Text("Time tracking")
        }
    }

    private var workSummary: String {
        TimeTrackingPolicy.workCategories(from: workCategories)
            .sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")
    }

    // MARK: Promises

    private var promiseSection: some View {
        Section {
            Defaults.Toggle(key: .enablePromiseKeeper) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep track of promises")
                    Text("When you write \u{201C}I'll send it tonight\u{201D} in WhatsApp or in a reply from the notch, NotchFlow adds it to Promises in the Todos tab and reminds you before it's due. A plan you say yes to (\u{201C}lunch tomorrow at 1?\u{201D} \u{2192} \u{201C}pakka\u{201D}) is kept too. English is understood on this Mac; for other languages, see below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Keep track of promises"))
            if promisesEnabled {
                Defaults.Toggle(key: .promiseTrackTheirs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also track what others promise me")
                        Text("\u{201C}I'll send the invoice Monday\u{201D} becomes \u{201C}waiting on\u{201D}, with a polite reminder ready if it doesn't come.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Also track what others promise me"))
                Defaults.Toggle(key: .promiseReadMessagesHistory) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See what I send in Messages")
                        Text("Reads new iMessages and texts you send (from the Messages app or your iPhone) with the message you answered, so a plan you said yes to (\u{201C}coffee Friday 5 pm?\u{201D} \u{2192} \u{201C}okay bhai\u{201D}) is kept as \u{201C}Coffee with Rahul \u{00B7} Fri 5:00 PM\u{201D}. Needs Full Disk Access; only messages from now on, read on this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let status = keeper.messagesHistoryStatus {
                            Text(status).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .settingsHighlight(id: highlightID("See what I send in Messages"))
                Defaults.Toggle(key: .promiseUseAI) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Understand any language")
                        Text("Also finds promises in Hindi, Gujarati, Marathi and mixes like Hinglish (\u{201C}kal shaam tak bhej dunga\u{201D}, \u{201C}hu kale moklish\u{201D}, \u{201C}मी उद्या पाठवतो\u{201D}), using your AI provider from Settings \u{203A} Smart Tools. Only messages with a word that hints at a promise or a time are sent, a few at a time, at most 300 a day; \u{201C}ok\u{201D}, \u{201C}haha\u{201D} and the like never leave this Mac. Ollama or LM Studio keeps everything on this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                        if useAI && !AIClient.isReady() {
                            Text("Set up an AI provider in Settings \u{203A} Smart Tools first.")
                                .font(.caption).foregroundStyle(.orange)
                        } else if useAI, let status = keeper.aiStatus {
                            Text(status).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Understand any language"))
                Picker("Remind me", selection: $nudgeMinutes) {
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                    Text("When it's due").tag(0)
                }
                .settingsHighlight(id: highlightID("Remind me"))
                HStack {
                    Text("\(keeper.open.count) open")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear all promises", role: .destructive) { keeper.clearAll() }
                        .disabled(keeper.promises.isEmpty)
                }
            }
        } header: {
            Text("Promise keeper")
        }
    }

    // MARK: Window stash

    private var stashSection: some View {
        Section {
            Defaults.Toggle(key: .enableWindowStash) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window stash")
                    Text("A parking spot in the Flow tab for windows you need later but not now. Stash all others parks every window except the app in front; click one to bring it back exactly where it was.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Window stash"))
            Defaults.Toggle(key: .windowStashByDragging) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag windows into the notch to stash them")
                    Text("Drag a window by its title bar up past the top of the screen, into the notch. The notch shows \u{201C}Stash \u{00B7} drop here\u{201D} as you get close and \u{201C}Let go to stash\u{201D} when you're on the spot (the trackpad taps too).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Drag windows into the notch to stash them"))
            KeyboardShortcuts.Recorder("Stash the front window:", name: .stashFrontWindow)
            HStack {
                Text(previewsAllowed ? "Window previews are on." : "Previews need Screen Recording; until then, app icons stand in.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !previewsAllowed {
                    Button("Show previews") {
                        _ = CGRequestScreenCaptureAccess()
                        previewsAllowed = CGPreflightScreenCaptureAccess()
                    }
                }
            }
        } header: {
            Text("Window stash")
        } footer: {
            Text("Needs Accessibility. Stashed windows are minimized; bringing one back from the Dock removes it from the stash.")
        }
    }

    // MARK: Workspaces

    private var workspaceSection: some View {
        Section {
            Defaults.Toggle(key: .enableWorkspaces) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspaces")
                    Text("Arrange your windows, then Save current in the Flow tab: one tap later puts every window back where it was and as big as it was, opening the apps (or windows) that are closed. Setups can also turn on Focus, music and a Pomodoro. Done for the day closes the apps again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Workspaces"))
            if workspacesEnabled {
                ForEach(workspaces.workspaces) { workspace in
                    HStack(spacing: 10) {
                        Image(systemName: workspace.symbol).frame(width: 20).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.name)
                            Text(workspace.apps.map(\.name).joined(separator: ", ").ifEmpty("No apps yet"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Open") { workspaces.open(workspace) }
                        Button("Update") { Task { await workspaces.updateFromCurrent(workspace.id) } }
                            .help("Replace this setup with the apps, window positions and sizes, and browser tabs open now.")
                        Button("Edit") { editing = workspace }
                        Button(role: .destructive) { workspaces.delete(workspace.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("New workspace") { editing = Workspace(name: "Work") }
                    Button("Save what's open now") {
                        Task { editing = await workspaces.captureCurrentSetup(named: "Setup \(workspaces.workspaces.count + 1)") }
                    }
                    Spacer()
                }
                Defaults.Toggle(key: .workspaceSuggestions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggest workspaces")
                        Text("When you open the same apps together on several days, the Flow tab offers to save them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Suggest workspaces"))
                Defaults.Toggle(key: .workspaceDoneQuitsApps) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Done for the day quits workspace apps")
                        Text("Only apps a workspace opened today; apps still ask to save your work.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Done for the day quits workspace apps"))
            }
        } header: {
            Text("Workspaces")
        } footer: {
            Text("Saving and restoring window positions needs Accessibility, and Focus uses the two Shortcuts set up under Settings > Timers > Also silence macOS (Focus).")
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// Edits one workspace.
struct WorkspaceEditor: View {
    @State var workspace: Workspace
    let onDone: (Workspace?) -> Void
    @State private var urlText = ""

    private static let symbols = ["briefcase.fill", "book.fill", "chevron.left.forwardslash.chevron.right", "paintbrush.fill",
                                  "graduationcap.fill", "music.note", "camera.fill", "chart.bar.fill", "house.fill", "moon.fill"]

    init(workspace: Workspace, onDone: @escaping (Workspace?) -> Void) {
        _workspace = State(initialValue: workspace)
        _urlText = State(initialValue: workspace.urls.joined(separator: "\n"))
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $workspace.name)
                    Picker("Icon", selection: $workspace.symbol) {
                        ForEach(Self.symbols, id: \.self) { Image(systemName: $0).tag($0) }
                    }
                }
                Section("Apps") {
                    ForEach(workspace.apps, id: \.bundleID) { app in
                        HStack {
                            Text(app.name)
                            if let count = app.windows?.count, count > 0 {
                                Text("\(count) window\(count == 1 ? "" : "s") in place").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { workspace.apps.removeAll { $0.bundleID == app.bundleID } } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Menu("Add an open app") {
                            ForEach(runningApps, id: \.bundleID) { app in
                                Button(app.name) { add(app) }
                            }
                        }
                        Button("Choose an app…") { chooseApp() }
                    }
                }
                Section {
                    TextEditor(text: $urlText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 60)
                } header: {
                    Text("Web pages, one per line")
                }
                Section("Folders") {
                    ForEach(workspace.folders, id: \.self) { folder in
                        HStack {
                            Text((folder as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) { workspace.folders.removeAll { $0 == folder } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add a folder…") { if let path = chooseFolder() { workspace.folders.append(path) } }
                    Text("Folders open in the workspace's code editor if it has one (VS Code, Cursor, Zed, Xcode…), otherwise in Finder.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Terminal in")
                        Text(workspace.terminalFolder.isEmpty ? "None" : (workspace.terminalFolder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { if let path = chooseFolder() { workspace.terminalFolder = path } }
                        if !workspace.terminalFolder.isEmpty { Button("Clear") { workspace.terminalFolder = "" } }
                    }
                }
                Section("When it opens") {
                    Picker("Windows", selection: $workspace.layout) {
                        ForEach(Workspace.Layout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if workspace.layout == .restore {
                        let saved = workspace.apps.reduce(0) { $0 + ($1.windows?.count ?? 0) }
                        Text(saved == 0
                             ? "No window positions saved yet. Arrange your windows, then use Update next to this workspace (or Update to current layout in the Flow tab)."
                             : "\(saved) window\(saved == 1 ? "" : "s") go back to the exact position and size they had when saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Hide other apps", isOn: $workspace.hideOtherApps)
                    Toggle("Turn on Focus (Do Not Disturb)", isOn: $workspace.turnOnFocus)
                    Toggle("Start a Pomodoro", isOn: $workspace.startPomodoro)
                    Toggle("Play music", isOn: $workspace.playMusic)
                    if workspace.playMusic {
                        TextField("Apple Music playlist (optional)", text: $workspace.playlist)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { onDone(nil) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    workspace.urls = urlText.split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    workspace.name = workspace.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Workspace" : workspace.name
                    onDone(workspace)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 600)
    }

    private var runningApps: [WorkspaceApp] {
        let own = Bundle.main.bundleIdentifier ?? ""
        let current = Set(workspace.apps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> WorkspaceApp? in
                guard let id = app.bundleIdentifier, id != own, !current.contains(id) else { return nil }
                return WorkspaceApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: WorkspaceApp) {
        guard !workspace.apps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        workspace.apps.append(app)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(WorkspaceApp(bundleID: id, name: name))
        }
    }

    private func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
