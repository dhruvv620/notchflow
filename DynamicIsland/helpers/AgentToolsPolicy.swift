// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// The command-line AI tools NotchFlow can start: which ones there are, how to
// find them on this Mac, and the line typed into a terminal to start one in a
// folder. Pure, tested in tests/AgentToolsRegression.swift.

struct AgentTool: Codable, Equatable, Identifiable, Sendable {
    /// "claude", "codex"… or a custom tool's UUID string.
    let id: String
    var name: String
    /// What's typed to start it ("claude", "ollama run llama3").
    var command: String
    /// One letter for its icon.
    var monogram: String
    /// Its colour as "#RRGGBB".
    var color: String
    /// How to install it, as one shell line (empty for custom tools).
    var install: String = ""
    var isCustom = false

    /// The program to look for on PATH: the command's first word.
    var executable: String {
        command.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? command
    }
}

enum AgentToolsPolicy {
    static let builtIn: [AgentTool] = [
        AgentTool(id: "claude", name: "Claude Code", command: "claude", monogram: "C", color: "#E08A5F",
                  install: "npm install -g @anthropic-ai/claude-code"),
        AgentTool(id: "codex", name: "Codex", command: "codex", monogram: "X", color: "#3FBF9B",
                  install: "npm install -g @openai/codex"),
        AgentTool(id: "gemini", name: "Gemini CLI", command: "gemini", monogram: "G", color: "#6F9BFF",
                  install: "npm install -g @google/gemini-cli"),
        AgentTool(id: "cursor", name: "Cursor Agent", command: "cursor-agent", monogram: "U", color: "#B58CFF",
                  install: "curl https://cursor.com/install -fsS | bash"),
        AgentTool(id: "opencode", name: "OpenCode", command: "opencode", monogram: "O", color: "#F2C14E",
                  install: "npm install -g opencode-ai"),
        AgentTool(id: "aider", name: "Aider", command: "aider", monogram: "A", color: "#4FC3E8",
                  install: "python3 -m pip install aider-install && aider-install"),
        AgentTool(id: "copilot", name: "Copilot CLI", command: "copilot", monogram: "P", color: "#D0D0D0",
                  install: "npm install -g @github/copilot"),
    ]

    /// Shown in the notch until you choose.
    static let defaultShown = ["claude", "codex", "gemini", "cursor"]

    /// The palette for custom tools, picked by name so it stays the same.
    static let customColors = ["#F28AB2", "#9CD86B", "#FF9F5A", "#7FD3C8", "#C5A3FF"]

    static func customTool(id: String, name: String, command: String) -> AgentTool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = trimmed.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
        let index = abs(trimmed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }) % customColors.count
        return AgentTool(id: id, name: trimmed.isEmpty ? command : trimmed,
                         command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                         monogram: letter, color: customColors[index], isCustom: true)
    }

    /// All tools: the built-in ones, then yours.
    static func all(custom: [AgentTool]) -> [AgentTool] { builtIn + custom }

    /// The tools to show as Start icons, in catalog order.
    static func shown(_ ids: [String], custom: [AgentTool]) -> [AgentTool] {
        let wanted = Set(ids)
        return all(custom: custom).filter { wanted.contains($0.id) }
    }

    // MARK: Finding tools

    /// A shell script that prints the name of each program it finds.
    static func detectionScript(for tools: [AgentTool]) -> String {
        let names = Array(Set(tools.map(\.executable))).sorted().map(shellQuoted).joined(separator: " ")
        return "for c in \(names); do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done; true"
    }

    /// The ids of the tools whose programs were found, from the script's output.
    static func installed(from output: String, tools: [AgentTool]) -> Set<String> {
        let found = Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        return Set(tools.filter { found.contains($0.executable) }.map(\.id))
    }

    // MARK: Starting a tool

    /// Typed into a new shell: go to the folder, clear the screen, start the tool.
    static func startLine(tool: AgentTool, folder: String) -> String {
        "cd \(shellQuoted(folder)) && clear && \(tool.command)\n"
    }

    /// The command for an external terminal window.
    static func externalCommand(tool: AgentTool, folder: String) -> String {
        "cd \(shellQuoted(folder)) && \(tool.command)"
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Folders to offer: the tool's last one first, then recent projects, no repeats.
    static func folders(last: String?, recent: [String], projects: [String], limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for folder in [last].compactMap({ $0 }) + recent + projects {
            let path = (folder as NSString).standardizingPath
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            out.append(path)
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Agent tabs

    /// The hook agent kind ("claude-code", "codex", "gemini", "cursor") for a tool id.
    static func agentKind(forTool id: String) -> String? {
        switch id {
        case "claude": return "claude-code"
        case "codex": return "codex"
        case "gemini": return "gemini"
        case "cursor": return "cursor"
        default: return nil
        }
    }
}
