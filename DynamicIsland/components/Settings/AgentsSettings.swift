// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

/// Settings > AI Agents: connect agents, the notchflow command, and how approvals behave.
struct AgentsSettings: View {
    @ObservedObject private var hub = AgentHub.shared
    @Default(.enableAgentsFeature) private var enabled
    @Default(.agentApprovalWaitSeconds) private var waitSeconds
    @State private var claudeConnected = AgentSetup.isClaudeCodeConnected
    @State private var commandCurrent = AgentSetup.isCommandCurrent
    @State private var message: String?
    @State private var confirmConnect = false
    @State private var copiedPath = false

    private func highlightID(_ title: String) -> String { SettingsTab.agents.highlightID(for: title) }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAgentsFeature) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Agents")
                        Text("Approve what agents want to do, answer their questions and follow their progress from the notch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("AI Agents"))
                if enabled {
                    HStack(spacing: 6) {
                        Circle().fill(hub.isBridgeRunning ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(hub.isBridgeRunning ? "Listening for agents on this Mac only" : (hub.bridgeError ?? "Starting…"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if enabled {
                claudeCodeSection
                approvalsSection
                commandSection
                otherAgentsSection
            }
        }
        .onAppear(perform: refresh)
        .alert("Connect Claude Code?", isPresented: $confirmConnect) {
            Button("Connect") { connectClaudeCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AgentSetup.claudeCodeChangeSummary + "\n\nYour existing settings and hooks are kept, and a backup of settings.json is saved next to it.")
        }
    }

    // MARK: Claude Code

    private var claudeCodeSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(.orange).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code")
                    Text(claudeConnected
                         ? "Connected. New Claude Code sessions report to the notch."
                         : "Not connected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if claudeConnected {
                    Button("Disconnect", role: .destructive) { disconnectClaudeCode() }
                } else {
                    Button("Connect") { confirmConnect = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .settingsHighlight(id: highlightID("Claude Code"))
            if claudeConnected {
                Text("Already running sessions pick it up after you restart them. Approvals wait in the notch; everything else (progress, questions, done) appears as it happens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("Claude Code's hooks call the notchflow command, which asks NotchFlow and passes your answer back. If NotchFlow is closed, Claude Code asks in the terminal as usual.")
        }
    }

    // MARK: Approvals

    private var approvalsSection: some View {
        Section {
            Picker("Wait for an answer in the notch", selection: $waitSeconds) {
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
                Text("10 minutes").tag(600)
            }
            .settingsHighlight(id: highlightID("Wait for an answer in the notch"))
            Text("While an approval waits in the notch, the agent's own prompt is held back; after this long it asks in its window instead. Nothing is ever approved on its own.")
                .font(.caption).foregroundStyle(.secondary)
            Defaults.Toggle(key: .agentAskInWindowWhenInFront) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask in the agent's window when it is in front")
                    Text("If you are already looking at Claude Code's terminal, it asks there right away.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Ask in the agent's window when it is in front"))
            Defaults.Toggle(key: .agentShowWorkingInClosedNotch) {
                Text("Show working agents under the closed notch")
            }
            .settingsHighlight(id: highlightID("Show working agents under the closed notch"))
            Button("Send a test approval") { hub.sendTestRequest() }
                .disabled(!hub.isBridgeRunning)
        } header: {
            Text("Approvals")
        }
    }

    // MARK: The notchflow command

    private var commandSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("notchflow command")
                    Text(commandCurrent ? AgentSetup.commandURL.path : "Not installed")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Button(commandCurrent ? "Reinstall" : "Install") {
                    do {
                        try AgentSetup.installCommand()
                        message = "Installed \(AgentSetup.commandURL.path)."
                    } catch {
                        message = error.localizedDescription
                    }
                    refresh()
                }
            }
            .settingsHighlight(id: highlightID("notchflow command"))
            Text("Use it from scripts and other agents: `notchflow ask \"Deploy?\" --options \"Deploy,Cancel\"` waits for your choice in the notch, `notchflow notify \"Backup done\"` shows a message, `notchflow status` checks the connection. To type it in Terminal, add ~/.local/bin to your PATH.")
                .font(.caption).foregroundStyle(.secondary)
            Button(copiedPath ? "Copied" : "Copy the PATH line for ~/.zshrc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("export PATH=\"$HOME/.local/bin:$PATH\"", forType: .string)
                copiedPath = true
            }
            .controlSize(.small)
        } header: {
            Text("Command line")
        }
    }

    private var otherAgentsSection: some View {
        Section {
            Text("Claude and ChatGPT apps: their notifications already appear in Notifications & Calls. They cannot be approved from another app.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Codex, Gemini CLI and Cursor: coming next through the same notchflow command. Any tool that can run a command can already use notchflow ask and notify.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Other agents")
        }
    }

    // MARK: Actions

    private func refresh() {
        claudeConnected = AgentSetup.isClaudeCodeConnected
        commandCurrent = AgentSetup.isCommandCurrent
    }

    private func connectClaudeCode() {
        do {
            let backup = try AgentSetup.connectClaudeCode(waitSeconds: waitSeconds)
            message = "Connected. " + (backup.map { "Backup: \($0.path)" } ?? "Created ~/.claude/settings.json.")
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    private func disconnectClaudeCode() {
        do {
            let backup = try AgentSetup.disconnectClaudeCode()
            message = "Disconnected; only NotchFlow's hooks were removed." + (backup.map { " Backup: \($0.path)" } ?? "")
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }
}
