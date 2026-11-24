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
    @ObservedObject private var workspaces = WorkspaceManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableOrbit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Orbit")
                        Text("Projects and people pages that build themselves from your day. Off means Orbit does nothing at all: no listeners, no timers, nothing in memory.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: "orbit-Use Orbit")
                if enableOrbit {
                    Defaults.Toggle(key: .orbitLoops) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loops")
                            Text("One inbox of what's still open: agents waiting on you, promises, unanswered messages, failing builds and Linear issues.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Defaults.Toggle(key: .orbitTeam) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Team")
                            Text("Your AI agents as a board: who's working, who's waiting on you. Right-click a loop to hand it to an agent in that project's folder.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Defaults.Toggle(key: .orbitTrackProjects) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Projects")
                            Text("From commands in the Terminal tab, AI agents, builds and focus time.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Defaults.Toggle(key: .orbitTrackPeople) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("People")
                            Text("Only people you pin (right-click a message or promise in Loops). Their messages and promises are kept on their page; message text only when it names one of your projects.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: orbit.isRunning ? "circle.fill" : "pause.circle")
                            .foregroundStyle(orbit.isRunning ? .green : .secondary)
                            .font(.caption)
                        Text(statusText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Orbit")
            } footer: {
                Text("Everything stays on this Mac, in Application Support › NotchFlow › Orbit.")
            }

            if enableOrbit {
                Section {
                    Defaults.Toggle(key: .orbitWriteVault) {
                        Text("Write notes to an Obsidian vault")
                    }
                    .settingsHighlight(id: "orbit-Obsidian vault")
                    if writeVault {
                        HStack {
                            Text("Vault")
                            Spacer()
                            Text(orbit.vaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button("Choose…", action: chooseVault)
                            if !vaultPath.isEmpty { Button("Default") { vaultPath = "" } }
                        }
                        Defaults.Toggle(key: .orbitDailyNotes) {
                            Text("Daily notes")
                        }
                        if orbit.hasObsidian {
                            if orbit.obsidianKnowsVault {
                                Label("Obsidian has this vault open", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            } else {
                                HStack(alignment: .top) {
                                    Label("Obsidian hasn't opened this folder yet. In Obsidian, choose Open folder as vault and pick the folder above. Links from the notch work after that.",
                                          systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                    Spacer()
                                    Button("Show Folder") {
                                        try? FileManager.default.createDirectory(at: orbit.vaultURL, withIntermediateDirectories: true)
                                        NSWorkspace.shared.activateFileViewerSelecting([orbit.vaultURL])
                                    }
                                }
                            }
                        } else {
                            Label("Obsidian isn't installed. The notes are plain markdown files; get Obsidian at obsidian.md to browse them as linked pages.",
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Write Now") { orbit.writeVaultNow() }.disabled(!orbit.isRunning)
                            Button("Open in Obsidian") { orbit.openInObsidian(nil) }
                            Spacer()
                            if let status = orbit.vaultStatus {
                                Text(status).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Obsidian vault")
                } footer: {
                    Text("Notes go in the vault's Orbit folder (Projects, People, Daily) with [[links]] between them. Orbit only rewrites the part between its markers; anything you write outside it is kept. A new folder is set up as a vault, so Obsidian can open it.")
                }

                Section {
                    Defaults.Toggle(key: .orbitDailyBrief) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Morning brief")
                            Text("Yesterday's work, today's meetings and what's open, as a notification and at the top of the daily note. One timer for that moment; nothing runs in between.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: "orbit-Morning brief")
                    if briefOn {
                        Picker("At", selection: $briefHour) {
                            ForEach(5..<13, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                    }
                    Defaults.Toggle(key: .orbitScenes) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scenes")
                            Text("One click sets you up: open a workspace, hold notifications, open a terminal in the project, start an agent on a task.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: "orbit-Scenes")
                    if scenesOn && orbit.isRunning {
                        ForEach(orbit.state.scenes) { scene in
                            sceneEditor(scene)
                        }
                        Button("Add Scene") { orbit.saveScene(OrbitScene(name: "New scene")) }
                    }
                } header: {
                    Text("Today")
                }

                Section {
                    Defaults.Toggle(key: .orbitLinear) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect Linear")
                            Text("Your open assigned issues appear in Loops (Start and Done move them in Linear), and anything in Orbit can become a Linear issue. Checks every five minutes while on.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: "orbit-Linear")
                    if linearOn {
                        HStack {
                            SecureField(linear.hasKey ? "API key saved (paste a new one to replace it)" : "Personal API key (lin_api_…)", text: $linearKey)
                            Button("Save") {
                                linear.saveKey(linearKey)
                                linearKey = ""
                            }
                            .disabled(linearKey.trimmingCharacters(in: .whitespaces).isEmpty)
                            if linear.hasKey {
                                Button("Remove") { linear.saveKey("") }
                            }
                        }
                        HStack {
                            if let name = linear.accountName {
                                Label("Connected as \(name), \(linear.issues.count) open issues", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if let error = linear.lastError {
                                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            } else {
                                Text("Make a key in Linear: Settings › Account › Security & access › Personal API keys.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Check Now") { Task { await linear.refresh() } }
                                .disabled(!linear.isActive || linear.isRefreshing)
                        }
                        .font(.caption)
                        if !linear.teams.isEmpty {
                            Picker("New issues go to", selection: $linearTeam) {
                                Text("First team").tag("")
                                ForEach(linear.teams) { team in
                                    Text("\(team.name) (\(team.key))").tag(team.id)
                                }
                            }
                        }
                        Defaults.Toggle(key: .orbitLinearAgentComments) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comment when an agent finishes an issue")
                                Text("When an AI agent's task names one of your issues (like ENG-12), Orbit adds a comment to it when the agent is done.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Linear")
                } footer: {
                    Text("The key is kept in your Keychain. Off means no requests to Linear at all.")
                }

                Section {
                    Button("Forget Everything…", role: .destructive) { confirmForget = true }
                        .disabled(!orbit.isRunning)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Deletes Orbit's saved projects, people and timeline. Notes already in the vault stay.")
                }
            }
        }
        .confirmationDialog("Forget everything Orbit kept?", isPresented: $confirmForget) {
            Button("Forget Everything", role: .destructive) { orbit.forgetEverything() }
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

    private var statusText: String {
        guard orbit.isRunning else { return "Paused: turn on a part above." }
        let state = orbit.state
        return "Running: \(state.projects.count) projects, \(state.people.count) people, \(state.events.count) events."
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
