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
    @State private var confirmForget = false

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
                            Text("From messages and promises. Message text is kept only when it names one of your projects.")
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

    private var statusText: String {
        guard orbit.isRunning else { return "Paused: turn on Projects or People." }
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
