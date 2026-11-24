// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI

/// Settings › Orbit: the master switch, a switch for each part, and the
/// Obsidian vault.
struct OrbitSettings: View {
    @ObservedObject private var orbit = Orbit.shared
    @Default(.enableOrbit) private var enableOrbit
    @Default(.orbitTrackProjects) private var trackProjects
    @Default(.orbitTrackPeople) private var trackPeople
    @Default(.orbitWriteVault) private var writeVault
    @Default(.orbitVaultPath) private var vaultPath
    @Default(.orbitLinear) private var linearOn
    @Default(.orbitLinearTeam) private var linearTeam
    @ObservedObject private var linear = OrbitLinear.shared
    @State private var confirmForget = false
    @State private var linearKey = ""
    @Default(.orbitDailyBrief) private var briefOn
    @Default(.orbitBriefHour) private var briefHour
    @Default(.orbitScenes) private var scenesOn
    @Default(.orbitTeam) private var teamOn
    @ObservedObject private var workspaces = WorkspaceManager.shared

    var body: some View {
        Form {
            Section {
                SettingsPageHeader(symbol: "circle.circle", tint: SettingsPalette.work, title: "Orbit",
                                   detail: "Projects, people and loose ends that keep track of themselves. Everything stays on this Mac.",
                                   status: headerStatus, isOn: $enableOrbit)
                    .settingsHighlight(id: "orbit-Use Orbit")
            }

            if !enableOrbit {
                Section {
                    Text("Off: Orbit does nothing at all. No listeners, no timers, nothing in memory.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                partsSection
                todaySection
                vaultSection
                linearSection
                dataSection
            }
        }
        .confirmationDialog("Forget everything Orbit kept?", isPresented: $confirmForget) {
            Button("Forget Everything", role: .destructive) { orbit.forgetEverything() }
        } message: {
            Text("Its projects, people and timeline are deleted. Notes already in your vault stay.")
        }
    }

    private var headerStatus: SettingsStatus? {
        guard enableOrbit else { return nil }
        guard orbit.isRunning else { return SettingsStatus(text: "Paused: turn on a part below", kind: .warn) }
        let state = orbit.state
        return SettingsStatus(text: "Running · \(state.projects.count) projects, \(state.people.count) people, \(state.events.count) events", kind: .ok)
    }

    // MARK: Sections

    private var partsSection: some View {
        Section {
            SettingsToggle(key: .orbitLoops, title: "Loops",
                           detail: "What's still open, in one list: agents waiting, promises, replies, failing builds, Linear issues.")
            SettingsToggle(key: .orbitTeam, title: "Team",
                           detail: "Your AI agents as a board. Right-click a loop to hand it to an agent.")
            if teamOn {
                SettingsToggle(key: .orbitBackgroundHandoffs, title: "Hand-offs work in the background",
                               detail: "Claude Code and Codex work in their own copy of the project, so your files aren't touched. You review before anything is kept.")
                    .padding(.leading, 16)
            }
            SettingsToggle(key: .orbitTrackProjects, title: "Projects",
                           detail: "Pages that build themselves from the Terminal tab, AI agents, builds and focus time.")
            SettingsToggle(key: .orbitTrackPeople, title: "People",
                           detail: "Only people you pin: right-click a message or promise in Loops.")
        } header: {
            Text("Parts")
        }
    }

    private var todaySection: some View {
        Section {
            SettingsToggle(key: .orbitDailyBrief, title: "Morning brief",
                           detail: "Yesterday's work, today's meetings and what's open, as one notification.",
                           highlightID: "orbit-Morning brief")
            if briefOn {
                Picker("Brief at", selection: $briefHour) {
                    ForEach(5..<13, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .padding(.leading, 16)
            }
            SettingsToggle(key: .orbitFocusPlan, title: "Best focus hours",
                           detail: "Finds the two hours you do your deepest work and blocks them in one click.",
                           highlightID: "orbit-Best focus hours")
            SettingsToggle(key: .orbitScatter, title: "Notice when I'm scattered",
                           detail: "Jumping between 6+ apps in 10 minutes shows Scattered, with Focus 25 min one click away.")
            SettingsToggle(key: .orbitBillWatch, title: "Bills and renewals",
                           detail: "Renewals, trials ending and bills due show in Loops three days before.",
                           highlightID: "orbit-Bills and renewals")
            SettingsToggle(key: .orbitScenes, title: "Scenes",
                           detail: "One click sets you up: a workspace, quiet time, a terminal, an agent on a task.",
                           highlightID: "orbit-Scenes")
            if scenesOn && orbit.isRunning {
                ForEach(orbit.state.scenes) { scene in
                    sceneEditor(scene)
                }
                Button("Add Scene") { orbit.saveScene(OrbitScene(name: "New scene")) }
            }
        } header: {
            Text("Today")
        }
    }

    private var vaultSection: some View {
        Section {
            SettingsToggle(key: .orbitWriteVault, title: "Write notes to an Obsidian vault",
                           detail: "Projects, People and Daily notes with [[links]]. Your own writing in them is kept.",
                           highlightID: "orbit-Obsidian vault")
            if writeVault {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(orbit.vaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseVault)
                        if !vaultPath.isEmpty { Button("Default") { vaultPath = "" } }
                    }
                } label: {
                    Text("Folder")
                }
                SettingsToggle(key: .orbitDailyNotes, title: "Daily notes")
                vaultStatusRow
                HStack {
                    if let status = orbit.vaultStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open in Obsidian") { orbit.openInObsidian(nil) }
                    Button("Write Now") { orbit.writeVaultNow() }
                        .settingsPrimaryButton()
                        .disabled(!orbit.isRunning)
                }
            }
        } header: {
            Text("Obsidian vault")
        }
    }

    @ViewBuilder private var vaultStatusRow: some View {
        if !orbit.hasObsidian {
            SettingsStatus(text: "Obsidian isn't installed. The notes are plain markdown; get Obsidian at obsidian.md to browse them.")
        } else if orbit.obsidianKnowsVault {
            SettingsStatus(text: "Obsidian has this vault open", kind: .ok)
        } else {
            HStack(alignment: .top) {
                SettingsStatus(text: "Obsidian hasn't opened this folder yet: in Obsidian, choose Open folder as vault.", kind: .warn)
                Spacer()
                Button("Show Folder") {
                    try? FileManager.default.createDirectory(at: orbit.vaultURL, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([orbit.vaultURL])
                }
            }
        }
    }

    private var linearSection: some View {
        Section {
            SettingsToggle(key: .orbitLinear, title: "Connect Linear",
                           detail: "Your assigned issues in Loops; Start and Done move them in Linear. Checks every five minutes while on.",
                           highlightID: "orbit-Linear")
            if linearOn {
                HStack {
                    SecureField(linear.hasKey ? "API key saved (paste a new one to replace it)" : "Personal API key (lin_api_…)", text: $linearKey)
                    Button("Save") {
                        linear.saveKey(linearKey)
                        linearKey = ""
                    }
                    .settingsPrimaryButton()
                    .disabled(linearKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if linear.hasKey {
                        Button("Remove") { linear.saveKey("") }
                            .settingsDestructiveButton()
                    }
                }
                HStack {
                    if let name = linear.accountName {
                        SettingsStatus(text: "Connected as \(name) · \(linear.issues.count) open issues", kind: .ok)
                    } else if let error = linear.lastError {
                        SettingsStatus(text: error, kind: .warn)
                    } else {
                        SettingsStatus(text: "Make a key in Linear: Settings › Account › Security & access › Personal API keys.")
                    }
                    Spacer()
                    Button("Check Now") { Task { await linear.refresh() } }
                        .disabled(!linear.isActive || linear.isRefreshing)
                }
                if !linear.teams.isEmpty {
                    Picker("New issues go to", selection: $linearTeam) {
                        Text("First team").tag("")
                        ForEach(linear.teams) { team in
                            Text("\(team.name) (\(team.key))").tag(team.id)
                        }
                    }
                }
                SettingsToggle(key: .orbitLinearAgentComments, title: "Comment when an agent finishes an issue",
                               detail: "When an agent's task names an issue (like ENG-12), Orbit comments on it when done.")
            }
        } header: {
            Text("Linear")
        } footer: {
            Text("The key is kept in your Keychain. Off means no requests to Linear at all.")
        }
    }

    private var dataSection: some View {
        Section {
            HStack {
                SettingsRowLabel(title: "Forget everything", detail: "Deletes Orbit's projects, people and timeline. Vault notes stay.")
                Spacer()
                Button("Forget…") { confirmForget = true }
                    .settingsDestructiveButton()
                    .disabled(!orbit.isRunning)
            }
        } header: {
            Text("Data")
        }
    }

    private func sceneEditor(_ scene: OrbitScene) -> some View {
        let binding = Binding<OrbitScene>(
            get: { orbit.state.scenes.first { $0.id == scene.id } ?? scene },
            set: { orbit.saveScene($0) }
        )
        return DisclosureGroup {
            TextField("Name", text: binding.name)
            Picker("Project", selection: binding.project) {
                Text("None").tag(String?.none)
                ForEach(orbit.state.projects.values.sorted { $0.name < $1.name }) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            Picker("Workspace", selection: binding.workspace) {
                Text("None").tag(UUID?.none)
                ForEach(workspaces.workspaces) { workspace in
                    Text(workspace.name).tag(Optional(workspace.id))
                }
            }
            Stepper(value: binding.quietMinutes, in: 0...240, step: 10) {
                Text(binding.wrappedValue.quietMinutes == 0 ? "Don't hold notifications" : "Hold notifications for \(binding.wrappedValue.quietMinutes) min")
            }
            Toggle("Open a Terminal tab in the project", isOn: binding.openTerminal)
            TextField("Agent task (optional)", text: binding.agentTask, axis: .vertical)
                .lineLimit(1...3)
            HStack {
                Spacer()
                Button("Run") { orbit.run(binding.wrappedValue) }
                Button("Delete", role: .destructive) { orbit.deleteScene(scene.id) }
            }
        } label: {
            Label(scene.name, systemImage: scene.symbol)
        }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use as Vault"
        panel.message = "Choose your Obsidian vault (or an empty folder for a new one)."
        if panel.runModal() == .OK, let url = panel.url {
            vaultPath = url.path
            orbit.writeVaultNow()
        }
    }
}
