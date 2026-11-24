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
            HStack(spacing: 8) {
                TextField("Name", text: $newName, prompt: Text("Name, like Local Llama"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                TextField("Command", text: $newCommand, prompt: Text("Command, like ollama run llama3"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Button("Add Tool") {
                    tools.addCustom(name: newName, command: newCommand)
                    newName = ""
                    newCommand = ""
                }
                .settingsPrimaryButton()
                .disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                SettingsStatus(text: tools.isChecking ? "Looking for tools…" : "Looked for when this page opens.")
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
            Text("Switched-on tools get a Start icon in the AI Agents tab. It opens the tool in a project folder in the notch's Terminal (hold ⌥ for your terminal app).")
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
            Spacer(minLength: 8)
            if tools.hasChecked && !found && !tool.install.isEmpty {
                Button("Install…") { tools.install(tool) }
                    .help(tool.install)
            }
            if tool.isCustom {
                Button { tools.removeCustom(tool) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(SettingsPalette.danger)
                    .help("Remove \(tool.name)")
                    .accessibilityLabel("Remove \(tool.name)")
            }
            Toggle("Start icon for \(tool.name)", isOn: Binding(get: { shownIDs.contains(tool.id) },
                                                 set: { tools.setShown($0, tool) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .help("A Start icon for \(tool.name) in the notch")
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
