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
    @State private var confirmClearPromises = false

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
        .confirmationDialog("Clear every promise?", isPresented: $confirmClearPromises) {
            Button("Clear Promises", role: .destructive) { keeper.clearAll() }
        } message: {
            Text("Open and done promises are deleted. This can't be undone.")
        }
    }

    // MARK: Time tracking

    private var timeSection: some View {
        Section {
            SettingsToggle(key: .timeTrackingEnabled, title: "Track where my time goes",
                           detail: "Adds up your day by app, website and project. Idle time doesn't count. Stays on this Mac.",
                           highlightID: highlightID("Track where my time goes"))
            if trackingEnabled {
                SettingsToggle(key: .timeTrackingSites, title: "Tell websites apart",
                               detail: "Reads the front browser tab's address. macOS asks once per browser.",
                               highlightID: highlightID("Tell websites apart"))
                LabeledContent("Daily work goal") {
                    Stepper(value: $goalHours, in: 0.5...12, step: 0.5) {
                        Text("\(goalHours.formatted(.number.precision(.fractionLength(0...1)))) h")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
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
                SettingsToggle(key: .timeTrackingShowRing, title: "Show the work ring under the closed notch", detail: "How close you are to today's goal.", highlightID: highlightID("Show the work ring under the closed notch"))
                SettingsToggle(key: .timeTrackingWeeklyReport, title: "Weekly report on Friday afternoon", detail: "Where your week went, as one notification.", highlightID: highlightID("Weekly report on Friday afternoon"))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("More projects", text: $extraProjects, prompt: Text("acme-site, thesis, client-x"))
                    Text("Projects are found by themselves. Add other names, comma separated, to spot them anywhere.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .settingsHighlight(id: highlightID("Project names"))
                HStack {
                    SettingsRowLabel(title: "Your hours")
                    Spacer()
                    Button("Export CSV…") { tracker.exportCSV() }
                    Button("Erase…") { confirmClearTime = true }
                        .settingsDestructiveButton()
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
            SettingsToggle(key: .enablePromiseKeeper, title: "Keep track of promises",
                           detail: "“I'll send it tonight” becomes a reminder in Todos before it's due.",
                           highlightID: highlightID("Keep track of promises"))
            if promisesEnabled {
                SettingsToggle(key: .promiseTrackTheirs, title: "Also track what others promise me",
                               detail: "“I'll send the invoice Monday” becomes “waiting on”.",
                               highlightID: highlightID("Also track what others promise me"))
                SettingsToggle(key: .promiseReadMessagesHistory, title: "See what I send in Messages",
                               detail: "Plans you agree to in iMessage are kept too. Needs Full Disk Access.",
                               highlightID: highlightID("See what I send in Messages"))
                if let status = keeper.messagesHistoryStatus {
                    SettingsStatus(text: status, kind: .warn).padding(.leading, 16)
                }
                SettingsToggle(key: .promiseUseAI, title: "Understand any language",
                               detail: "Hindi, Gujarati, Hinglish and more, using your AI provider. Only likely promises are sent.",
                               highlightID: highlightID("Understand any language"))
                if useAI && !AIClient.isReady() {
                    SettingsStatus(text: "Set up an AI provider in Smart Tools first.", kind: .warn).padding(.leading, 16)
                } else if useAI, let status = keeper.aiStatus {
                    SettingsStatus(text: status, kind: .warn).padding(.leading, 16)
                }
                Picker("Remind me", selection: $nudgeMinutes) {
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                    Text("When it's due").tag(0)
                }
                .settingsHighlight(id: highlightID("Remind me"))
                HStack {
                    SettingsRowLabel(title: "Clear all promises", detail: "\(keeper.open.count) open now.")
                    Spacer()
                    Button("Clear…") { confirmClearPromises = true }
                        .settingsDestructiveButton()
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
            SettingsToggle(key: .enableWindowStash, title: "Window stash",
                           detail: "A parking spot in the Flow tab for windows you need later.",
                           highlightID: highlightID("Window stash"))
            SettingsToggle(key: .windowStashByDragging, title: "Drag windows into the notch to stash them",
                           detail: "Drag a window by its title bar up into the notch.",
                           highlightID: highlightID("Drag windows into the notch to stash them"))
            LabeledContent("Stash the front window") {
                KeyboardShortcuts.Recorder(for: .stashFrontWindow)
            }
            HStack {
                SettingsStatus(text: previewsAllowed ? "Window previews are on." : "Previews need Screen Recording. App icons stand in until then.",
                               kind: previewsAllowed ? .ok : .neutral)
                Spacer()
                if !previewsAllowed {
                    Button("Allow Previews") {
                        _ = CGRequestScreenCaptureAccess()
                        previewsAllowed = CGPreflightScreenCaptureAccess()
                    }
                }
            }
        } header: {
            Text("Window stash")
        } footer: {
            Text("Needs Accessibility. Stashed windows are minimized.")
        }
    }

    // MARK: Workspaces

    private var workspaceSection: some View {
        Section {
            SettingsToggle(key: .enableWorkspaces, title: "Workspaces",
                           detail: "Save your windows and apps, then bring them all back in one tap from the Flow tab.",
                           highlightID: highlightID("Workspaces"))
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
                        Button { workspaces.delete(workspace.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(SettingsPalette.danger)
                            .help("Delete this workspace")
                    }
                }
                HStack {
                    Button("New Workspace") { editing = Workspace(name: "Work") }
                    Button("Save What's Open Now") {
                        Task { editing = await workspaces.captureCurrentSetup(named: "Setup \(workspaces.workspaces.count + 1)") }
                    }
                    Spacer()
                }
                SettingsToggle(key: .workspaceSuggestions, title: "Suggest workspaces",
                               detail: "When you open the same apps together often, Flow offers to save them.",
                               highlightID: highlightID("Suggest workspaces"))
                SettingsToggle(key: .workspaceDoneQuitsApps, title: "Done for the day quits workspace apps",
                               detail: "Only apps a workspace opened today. They still ask to save.",
                               highlightID: highlightID("Done for the day quits workspace apps"))
            }
        } header: {
            Text("Workspaces")
        } footer: {
            Text("Putting windows back needs Accessibility. Focus uses the two shortcuts from Timers › Also silence macOS.")
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
