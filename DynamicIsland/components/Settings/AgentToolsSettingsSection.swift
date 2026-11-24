// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

/// Settings › AI Agents › Command-line tools: which AI tools are on this Mac,
/// which get a Start icon in the notch, installing them, and adding your own.
struct AgentToolsSettingsSection: View {
    @ObservedObject private var tools = AgentTools.shared
    @Default(.agentToolsShown) private var shownIDs
    @State private var newName = ""
    @State private var newCommand = ""

    var body: some View {
        Section {
            ForEach(tools.all) { tool in row(tool) }
            HStack {
                TextField("Name", text: $newName, prompt: Text("Name (say, Local Llama)"))
                    .frame(maxWidth: 170)
                TextField("Command", text: $newCommand, prompt: Text("Command (say, ollama run llama3)"))
                Button("Add") {
                    tools.addCustom(name: newName, command: newCommand)
                    newName = ""
                    newCommand = ""
                }
                .settingsPrimaryButton()
                .disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Text(tools.isChecking ? "Looking for tools…" : "Found with your shell's PATH, only when this page opens or you check.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check Again") { Task { await tools.check() } }
                    .disabled(tools.isChecking)
            }
            if let error = tools.lastError {
                Text(error).font(.caption).foregroundStyle(SettingsPalette.warn)
            }
        } header: {
            Text("Command-line tools")
        } footer: {
            Text("Tools with Show in notch get a Start icon at the top of the AI Agents tab: pick a project folder and the tool starts there in the notch's Terminal tab (hold ⌥ for your terminal app). Connect an agent below so its approvals and status show in the notch too.")
        }
        .settingsHighlight(id: "agents-Command-line tools")
        .onAppear { Task { await tools.check() } }
    }

    private func row(_ tool: AgentTool) -> some View {
        let found = tools.installed.contains(tool.id)
        return HStack(spacing: 10) {
            Text(tool.monogram)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color(tool.color)))
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                if tools.hasChecked {
                    SettingsStatus(text: status(tool, found: found), kind: found ? .ok : .neutral)
                } else {
                    Text(tool.command).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if tools.hasChecked && !found && !tool.install.isEmpty {
                Button("Install…") { tools.install(tool) }
                    .help(tool.install)
            }
            if tool.isCustom {
                Button { tools.removeCustom(tool) } label: { Image(systemName: "trash") }
                    .settingsDestructiveButton()
                    .help("Remove \(tool.name)")
                    .accessibilityLabel("Remove \(tool.name)")
            }
            Toggle("Show in notch", isOn: Binding(get: { shownIDs.contains(tool.id) },
                                                 set: { tools.setShown($0, tool) }))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func status(_ tool: AgentTool, found: Bool) -> String {
        if !tools.hasChecked { return tool.command }
        return found ? "Installed · \(tool.command)" : "Not found · \(tool.command)"
    }

    private func color(_ hex: String) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
