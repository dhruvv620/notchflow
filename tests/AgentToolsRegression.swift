// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct AgentToolsRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "AgentToolsRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = AgentToolsPolicy

        try require(Set(P.builtIn.map(\.id)).count == P.builtIn.count, "Unique ids")
        try require(P.builtIn.allSatisfy { !$0.install.isEmpty && $0.color.hasPrefix("#") && $0.monogram.count == 1 }, "Catalog complete")
        try require(P.builtIn.first { $0.id == "cursor" }?.executable == "cursor-agent", "Executable")

        let custom = P.customTool(id: "u1", name: "  local llama ", command: " ollama run llama3 ")
        try require(custom.name == "local llama" && custom.command == "ollama run llama3" && custom.executable == "ollama"
                    && custom.monogram == "L" && custom.isCustom, "Custom tool: \(custom)")
        try require(P.customTool(id: "u2", name: "", command: "x").name == "x", "Name falls back to command")
        try require(P.customTool(id: "u3", name: "local llama", command: "y").color == custom.color, "Stable colour")

        try require(P.shown(["gemini", "u1", "claude"], custom: [custom]).map(\.id) == ["claude", "gemini", "u1"], "Shown in order")

        let script = P.detectionScript(for: [P.builtIn[0], custom, P.builtIn[0]])
        try require(script == #"for c in 'claude' 'ollama'; do command -v "$c" >/dev/null 2>&1 && echo "$c"; done; true"#, "Script: \(script)")
        let installed = P.installed(from: "claude\n ollama \n\nother\n", tools: P.builtIn + [custom])
        try require(installed == ["claude", "u1"], "Installed: \(installed)")

        let tool = P.builtIn[0]
        try require(P.startLine(tool: tool, folder: "/Users/d/My Code/it's") == "cd '/Users/d/My Code/it'\\''s' && clear && claude\n", "Start line")
        try require(P.externalCommand(tool: custom, folder: "/r") == "cd '/r' && ollama run llama3", "External")

        try require(P.folders(last: "/a/", recent: ["/b", "/a", "/c"], projects: ["/c", "/d"], limit: 3) == ["/a", "/b", "/c"], "Folders")
        try require(P.folders(last: nil, recent: [], projects: []).isEmpty, "No folders")

        try require(P.agentKind(forTool: "claude") == "claude-code" && P.agentKind(forTool: "aider") == nil, "Kinds")
        print("Agent tools: all checks passed")
    }
}
