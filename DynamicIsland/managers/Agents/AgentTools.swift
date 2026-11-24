// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import Foundation

extension Defaults.Keys {
    /// Tools shown as Start icons in the AI Agents tab (AgentTool ids).
    static let agentToolsShown = Key<[String]>("agentToolsShown", default: AgentToolsPolicy.defaultShown)
    /// Tools you added (JSON of [AgentTool]).
    static let agentCustomTools = Key<String>("agentCustomTools", default: "")
    /// The last folder each tool was started in.
    static let agentToolFolders = Key<[String: String]>("agentToolFolders", default: [:])
    /// The AI Agents tab's filter: "" for all agents, else an AgentKind raw value.
    static let agentTabFilter = Key<String>("agentTabFilter", default: "")
}

/// The command-line AI tools: which are installed (checked only when asked,
/// nothing runs in the background) and starting one in a folder, in the
/// notch's Terminal tab or your terminal app.
@MainActor
final class AgentTools: ObservableObject {
    static let shared = AgentTools()

    @Published private(set) var installed: Set<String> = []
    @Published private(set) var hasChecked = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?

    private init() {}

    var custom: [AgentTool] {
        guard let data = Defaults[.agentCustomTools].data(using: .utf8),
              let tools = try? JSONDecoder().decode([AgentTool].self, from: data) else { return [] }
        return tools
    }

    private func saveCustom(_ tools: [AgentTool]) {
        guard let data = try? JSONEncoder().encode(tools) else { return }
        Defaults[.agentCustomTools] = String(decoding: data, as: UTF8.self)
        objectWillChange.send()
    }

    var all: [AgentTool] { AgentToolsPolicy.all(custom: custom) }
    var shown: [AgentTool] { AgentToolsPolicy.shown(Defaults[.agentToolsShown], custom: custom) }

    func isShown(_ tool: AgentTool) -> Bool { Defaults[.agentToolsShown].contains(tool.id) }

    func setShown(_ shown: Bool, _ tool: AgentTool) {
        var ids = Defaults[.agentToolsShown].filter { $0 != tool.id }
        if shown { ids.append(tool.id) }
        Defaults[.agentToolsShown] = ids
        objectWillChange.send()
    }

    func addCustom(name: String, command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tool = AgentToolsPolicy.customTool(id: UUID().uuidString, name: name, command: trimmed)
        saveCustom(custom + [tool])
        setShown(true, tool)
        Task { await check() }
    }

    func removeCustom(_ tool: AgentTool) {
        saveCustom(custom.filter { $0.id != tool.id })
        setShown(false, tool)
    }

    // MARK: Finding them

    /// Looks for each tool in a login shell (your PATH), once per call.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let tools = all
        let script = AgentToolsPolicy.detectionScript(for: tools)
        let output = await Task.detached(priority: .userInitiated) { () -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = AgentTranscriptPolicy.shellInvocation(script)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
        installed = AgentToolsPolicy.installed(from: output, tools: tools)
        hasChecked = true
    }

    func checkIfNeeded() {
        guard !hasChecked else { return }
        Task { await check() }
    }

    // MARK: Starting one

    func lastFolder(_ tool: AgentTool) -> String? { Defaults[.agentToolFolders][tool.id] }

    /// Folders to offer for a tool: its last one, recent agent projects, Orbit's projects.
    func folders(for tool: AgentTool) -> [String] {
        let orbitRoots = Orbit.shared.isRunning ? Orbit.shared.state.projects.values
            .sorted { $0.lastActive > $1.lastActive }.compactMap(\.root) : []
        return AgentToolsPolicy.folders(last: lastFolder(tool), recent: AgentHub.shared.recentProjects, projects: orbitRoots)
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Starts the tool in `folder`: in the notch's Terminal tab, or (external,
    /// or with the Terminal tab off) in your terminal app.
    func launch(_ tool: AgentTool, in folder: String, external: Bool = false) {
        lastError = nil
        var folders = Defaults[.agentToolFolders]
        folders[tool.id] = folder
        Defaults[.agentToolFolders] = folders
        AgentHub.shared.rememberProject(folder)
        if !external && Defaults[.enableTerminalFeature] {
            TerminalManager.shared.newSession(in: folder, startupInput: AgentToolsPolicy.startLine(tool: tool, folder: folder))
            DynamicIslandViewCoordinator.shared.currentView = .terminal
            return
        }
        let terminal = AgentHookPolicy.TerminalApp(rawValue: Defaults[.agentTerminalApp]) ?? .terminal
        let script = AgentHookPolicy.appleScript(running: AgentToolsPolicy.externalCommand(tool: tool, folder: folder), in: terminal)
        Task { @MainActor in
            do {
                try await AppleScriptHelper.executeVoid(script)
            } catch {
                self.lastError = "Couldn't open \(terminal.rawValue): allow NotchFlow in System Settings › Privacy & Security › Automation."
            }
        }
    }

    /// Asks for a folder, then starts the tool there.
    func chooseFolderAndLaunch(_ tool: AgentTool, external: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Start \(tool.name)"
        panel.message = "Choose the project folder for \(tool.name)."
        if let last = lastFolder(tool) { panel.directoryURL = URL(fileURLWithPath: last) }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            launch(tool, in: url.path, external: external)
        }
    }

    /// Opens Terminal with the install command typed and run.
    func install(_ tool: AgentTool) {
        guard !tool.install.isEmpty else { return }
        let terminal = AgentHookPolicy.TerminalApp(rawValue: Defaults[.agentTerminalApp]) ?? .terminal
        let script = AgentHookPolicy.appleScript(running: tool.install, in: terminal)
        Task { @MainActor in
            try? await AppleScriptHelper.executeVoid(script)
        }
    }
}
