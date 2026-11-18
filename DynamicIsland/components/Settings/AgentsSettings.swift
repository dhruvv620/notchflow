// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI

/// Settings > AI Agents: connect agents, the notchflow command, and how approvals behave.
struct AgentsSettings: View {
    @ObservedObject private var hub = AgentHub.shared
    @Default(.enableAgentsFeature) private var enabled
    @Default(.agentApprovalWaitSeconds) private var waitSeconds
    @Default(.agentTerminalApp) private var terminalApp
    @State private var connected: Set<String> = []
    @State private var commandCurrent = AgentSetup.isCommandCurrent
    @State private var message: String?
    @State private var pendingConnect: AgentSetup.Connector?
    @State private var copiedPath = false

    // SettingsTab is private to SettingsView.swift; ids follow its "<tab>-<title>" form.
    private func highlightID(_ title: String) -> String { "agents-\(title)" }

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
                agentsSection
                approvalsSection
                newTaskSection
                commandSection
                otherAgentsSection
            }
        }
        .onAppear(perform: refresh)
        .alert("Connect \(pendingConnect?.agent.displayName ?? "")?",
               isPresented: Binding(get: { pendingConnect != nil }, set: { if !$0 { pendingConnect = nil } })) {
            Button("Connect") { if let connector = pendingConnect { connect(connector) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let connector = pendingConnect {
                Text(AgentSetup.changeSummary(connector) + "\n\nYour existing settings and hooks are kept, and a backup is saved next to the file.")
            }
        }
    }

    // MARK: Agents

    private var agentsSection: some View {
        Section {
            Text("Connect the agents you use. Each one keeps its own settings; NotchFlow only adds its hooks.")
                .font(.caption).foregroundStyle(.secondary)
                .settingsHighlight(id: highlightID("Connect an agent"))
            ForEach(AgentSetup.connectors) { connector in
                let isConnected = connected.contains(connector.id)
                HStack(spacing: 10) {
                    Image(systemName: connector.agent.symbol).foregroundStyle(.orange).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connector.agent.displayName)
                        Text(isConnected ? "Connected · \(connector.summary)" : connector.summary)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isConnected {
                        Button("Disconnect", role: .destructive) { disconnect(connector) }
                    } else {
                        Button("Connect") { pendingConnect = connector }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("Each agent's hooks call the notchflow command, which asks NotchFlow and passes your answer back. If NotchFlow is closed or you don't answer, the agent asks in its own window as usual. The Claude and ChatGPT apps show up through Notifications & Calls; they can't be approved from another app.")
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
            Text("Any tool that can run a command can use `notchflow ask` and `notchflow notify`, so scripts and other agents can ask you something in the notch today.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Other agents and scripts")
        }
    }

    // MARK: New task

    private var newTaskSection: some View {
        Section {
            Picker("Open new tasks in", selection: $terminalApp) {
                ForEach(AgentHookPolicy.TerminalApp.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }
            .settingsHighlight(id: highlightID("Open new tasks in"))
            Text("New task in the AI Agents tab opens the agent in a new window there with your prompt, in the folder you pick. macOS asks once to let NotchFlow control the terminal.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("New tasks")
        }
    }

    // MARK: Actions

    private func refresh() {
        connected = Set(AgentSetup.connectors.filter(AgentSetup.isConnected).map(\.id))
        commandCurrent = AgentSetup.isCommandCurrent
    }

    private func connect(_ connector: AgentSetup.Connector) {
        do {
            let backup = try AgentSetup.connect(connector, waitSeconds: waitSeconds)
            message = "\(connector.agent.displayName) connected. " + (connector.afterConnecting ?? "")
                + (backup.map { " Backup: \($0.path)" } ?? "")
        } catch {
            message = error.localizedDescription
        }
        pendingConnect = nil
        refresh()
    }

    private func disconnect(_ connector: AgentSetup.Connector) {
        do {
            let backup = try AgentSetup.disconnect(connector)
            message = "\(connector.agent.displayName) disconnected; only NotchFlow's hooks were removed." + (backup.map { " Backup: \($0.path)" } ?? "")
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }
}
