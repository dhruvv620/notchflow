// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Pure logic for AI agent integrations (Foundation only), so Build.command can
// check it alone: reading Claude Code hook events, describing what an agent
// wants to do, rating how risky it is, building the answers Claude Code
// expects, and adding or removing NotchFlow's hooks in its settings.json.
//
// Claude Code hook reference: https://code.claude.com/docs/en/hooks

/// An event a Claude Code hook sent to NotchFlow.
struct AgentHookEvent: @unchecked Sendable {
    let name: String
    let sessionID: String
    let cwd: String
    let toolName: String?
    let toolInput: [String: Any]
    /// Notification text or the submitted prompt.
    let message: String?
    /// The agent's final text for the turn (Stop, AfterAgent).
    var response: String? = nil
    let notificationType: String?
    /// SessionStart source or SessionEnd reason.
    let detail: String?
    /// Rules Claude Code proposes for "always allow" (PermissionRequest).
    let permissionSuggestions: [Any]

    var projectName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }

    static func parse(_ data: Data) -> AgentHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String else { return nil }
        let message = (object["message"] as? String) ?? (object["prompt"] as? String)
        let response = (object["last_assistant_message"] as? String) ?? (object["prompt_response"] as? String)
        var event = AgentHookEvent(
            name: name,
            sessionID: object["session_id"] as? String ?? "unknown",
            cwd: object["cwd"] as? String ?? "",
            toolName: object["tool_name"] as? String,
            toolInput: object["tool_input"] as? [String: Any] ?? [:],
            message: message,
            notificationType: object["notification_type"] as? String,
            detail: (object["source"] as? String) ?? (object["reason"] as? String),
            permissionSuggestions: object["permission_suggestions"] as? [Any] ?? []
        )
        event.response = response
        return event
    }
}

enum AgentRisk: Int, Comparable, Sendable {
    case normal = 0, caution = 1, danger = 2
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String? {
        switch self {
        case .normal: return nil
        case .caution: return "Check this"
        case .danger: return "Destructive"
        }
    }
}

/// One multiple-choice question from Claude Code's AskUserQuestion tool.
struct AgentQuestion: Equatable, Sendable {
    struct Option: Equatable, Sendable {
        let label: String
        let description: String
    }
    let question: String
    let header: String
    let options: [Option]
    let multiSelect: Bool
}

enum AgentHookPolicy {
    // MARK: Describing actions

    /// A short title and the detail to show for a tool call ("Run a command", "npm test").
    static func describe(tool: String, input: [String: Any]) -> (title: String, detail: String) {
        func string(_ key: String) -> String { (input[key] as? String) ?? "" }
        func file(_ key: String) -> String { (string(key) as NSString).lastPathComponent }
        switch tool {
        case "Bash", "run_shell_command": return ("Run a command", string("command"))
        case "Edit", "MultiEdit", "replace": return ("Edit \(file("file_path"))", string("file_path"))
        case "write_file": return ("Write \(file("file_path"))", string("file_path"))
        case "read_file", "read_many_files": return ("Read \(file("file_path"))", string("file_path"))
        case "web_fetch": return ("Open a web page", string("prompt"))
        case "google_web_search": return ("Search the web", string("query"))
        case "Write": return ("Write \(file("file_path"))", string("file_path"))
        case "NotebookEdit": return ("Edit notebook \(file("notebook_path"))", string("notebook_path"))
        case "Read": return ("Read \(file("file_path"))", string("file_path"))
        case "WebFetch":
            let host = URL(string: string("url"))?.host ?? string("url")
            return ("Open \(host)", string("url"))
        case "WebSearch": return ("Search the web", string("query"))
        case "Task", "Agent": return ("Start a helper agent", string("description"))
        case "AskUserQuestion": return ("Question", (input["questions"] as? [[String: Any]])?.first?["question"] as? String ?? "")
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                // mcp__server__tool
                let server = parts.count > 2 ? String(parts[1]) : "MCP"
                let name = parts.count > 2 ? parts[2...].joined(separator: "_") : tool
                return ("Use \(name) (\(server))", compactJSON(input))
            }
            return ("Use \(tool)", compactJSON(input))
        }
    }

    /// What the agent is doing, for the status line ("Running npm test").
    static func activity(tool: String, input: [String: Any]) -> String {
        let (_, detail) = describe(tool: tool, input: input)
        let shortDetail = String(detail.split(whereSeparator: \.isNewline).first ?? "").prefix(60)
        switch tool {
        case "Bash", "run_shell_command": return shortDetail.isEmpty ? "Running a command" : "Running \(shortDetail)"
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "replace", "write_file": return "Editing \((detail as NSString).lastPathComponent)"
        case "Read", "read_file", "read_many_files": return "Reading \((detail as NSString).lastPathComponent)"
        case "Grep", "Glob", "search_file_content", "glob", "list_directory": return "Searching the code"
        case "WebFetch", "WebSearch", "web_fetch", "google_web_search": return "Looking things up"
        case "Task", "Agent": return "Running a helper agent"
        case "TodoWrite": return "Planning"
        default: return tool.hasPrefix("mcp__") ? "Using \(describe(tool: tool, input: input).title.dropFirst(4))" : "Working"
        }
    }

    // MARK: Risk

    private static let dangerousPatterns = [
        #"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+"#, #"\bsudo\b"#, #"\bgit\s+push\b.*(--force|-f\b)"#,
        #"\bgit\s+reset\s+--hard\b"#, #"\bgit\s+clean\s+-[a-zA-Z]*f"#, #"\bmkfs\b"#, #"\bdd\s+if="#,
        #"(curl|wget)[^|]*\|\s*(ba|z)?sh\b"#, #"\bchmod\s+(-R\s+)?777\b"#, #">\s*/dev/(disk|sd)"#,
        #"\bdrop\s+(table|database)\b"#, #"\bkillall\b"#, #"\blaunchctl\s+(unload|remove)\b"#,
    ]
    private static let cautionPatterns = [
        #"\bgit\s+push\b"#, #"\bnpm\s+publish\b"#, #"\b(brew|npm|pip3?|cargo|gem)\s+(install|uninstall)\b"#,
        #"\bcurl\b"#, #"\bwget\b"#, #"\bssh\b"#, #"\bscp\b"#, #"\bdocker\s+(rm|rmi|system\s+prune)\b"#,
        #"\bkill\b"#, #"\bmv\b"#,
    ]
    private static let sensitivePaths = ["/.ssh/", "/.aws/", "/.gnupg/", "/etc/", ".env", "/Library/Keychains/", "id_rsa", "id_ed25519"]

    static func risk(tool: String, input: [String: Any]) -> AgentRisk {
        if tool == "Bash" || tool == "run_shell_command" {
            let command = (input["command"] as? String ?? "").lowercased()
            if dangerousPatterns.contains(where: { command.range(of: $0, options: .regularExpression) != nil }) { return .danger }
            if cautionPatterns.contains(where: { command.range(of: $0, options: .regularExpression) != nil }) { return .caution }
            return .normal
        }
        if ["Edit", "MultiEdit", "Write", "NotebookEdit", "replace", "write_file"].contains(tool) {
            let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? ""
            return sensitivePaths.contains(where: { path.contains($0) }) ? .danger : .normal
        }
        if tool.hasPrefix("mcp__") { return .caution }
        return .normal
    }

    // MARK: Questions

    static func questions(from input: [String: Any]) -> [AgentQuestion] {
        guard let raw = input["questions"] as? [[String: Any]] else { return [] }
        return raw.compactMap { item in
            guard let question = item["question"] as? String, !question.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentQuestion.Option? in
                guard let label = option["label"] as? String else { return nil }
                return AgentQuestion.Option(label: label, description: option["description"] as? String ?? "")
            }
            return AgentQuestion(question: question, header: item["header"] as? String ?? "",
                                 options: options, multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }

    // MARK: Answers Claude Code reads from the hook's output

    static func permissionAllow(alwaysRules: [Any]? = nil) -> Data {
        var decision: [String: Any] = ["behavior": "allow"]
        if let alwaysRules, !alwaysRules.isEmpty { decision["updatedPermissions"] = alwaysRules }
        return json(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
    }

    static func permissionDeny(message: String, interrupt: Bool = false) -> Data {
        json(["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                     "decision": ["behavior": "deny", "message": message, "interrupt": interrupt]]])
    }

    /// Answers AskUserQuestion: Claude Code needs the questions echoed back with an `answers` map.
    static func questionAnswers(input: [String: Any], answers: [String: String]) -> Data {
        var updated = input
        updated["answers"] = answers
        return json(["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                            "permissionDecision": "allow",
                                            "updatedInput": updated]])
    }

    // MARK: Installing hooks into each agent's settings

    enum HookMode: Sendable {
        /// The agent waits for the answer (approvals, questions).
        case waits
        /// Status only; answers at once and never opens a request.
        case status
        /// Claude Code only: runs in the background after a turn and wakes
        /// Claude with a reply typed in the notch (asyncRewake).
        case reply
    }

    struct HookEntry: Sendable {
        let event: String
        let matcher: String?
        let mode: HookMode
    }

    /// How an agent's settings file lays out hooks.
    enum ConfigStyle: Sendable {
        /// `{"hooks": {"Event": [{"matcher", "hooks": [{"type": "command", ...}]}]}}`
        /// (Claude Code and Codex CLI). `timeout` in seconds.
        case grouped(backgroundFlag: Bool)
        /// Same nesting, `timeout` in milliseconds, plus a `name` (Gemini CLI).
        case groupedMilliseconds
        /// `{"version": 1, "hooks": {"event": [{"command": ...}]}}` (Cursor).
        case flat
    }

    struct HookTarget: Sendable {
        /// The id in `notchflow hook <id>` and `/v1/hook/<id>`.
        let id: String
        let style: ConfigStyle
        let plan: [HookEntry]
        var marker: String { "hook \(id)" }
    }

    static let claudeCode = HookTarget(id: "claude-code", style: .grouped(backgroundFlag: true), plan: [
        HookEntry(event: "PermissionRequest", matcher: nil, mode: .waits),
        HookEntry(event: "PreToolUse", matcher: "AskUserQuestion", mode: .waits),
        HookEntry(event: "PreToolUse", matcher: "*", mode: .status),
        HookEntry(event: "PostToolUse", matcher: "*", mode: .status),
        HookEntry(event: "Notification", matcher: nil, mode: .status),
        HookEntry(event: "UserPromptSubmit", matcher: nil, mode: .status),
        HookEntry(event: "Stop", matcher: nil, mode: .status),
        HookEntry(event: "Stop", matcher: nil, mode: .reply),
        HookEntry(event: "SessionStart", matcher: nil, mode: .status),
        HookEntry(event: "SessionEnd", matcher: nil, mode: .status),
    ])

    /// Codex CLI hooks follow Claude Code's event names and answers; Codex
    /// only runs them after you trust them in its /hooks screen.
    static let codex = HookTarget(id: "codex", style: .grouped(backgroundFlag: false), plan: [
        HookEntry(event: "PermissionRequest", matcher: nil, mode: .waits),
        HookEntry(event: "PreToolUse", matcher: "*", mode: .status),
        HookEntry(event: "UserPromptSubmit", matcher: nil, mode: .status),
        HookEntry(event: "Stop", matcher: nil, mode: .status),
        HookEntry(event: "SessionStart", matcher: nil, mode: .status),
    ])

    /// Gemini CLI hooks cannot hand a decision back to Gemini's own prompt,
    /// so Gemini reports status and "needs you" only.
    static let gemini = HookTarget(id: "gemini", style: .groupedMilliseconds, plan: [
        HookEntry(event: "BeforeAgent", matcher: nil, mode: .status),
        HookEntry(event: "BeforeTool", matcher: ".*", mode: .status),
        HookEntry(event: "Notification", matcher: nil, mode: .status),
        HookEntry(event: "AfterAgent", matcher: nil, mode: .status),
        HookEntry(event: "SessionStart", matcher: nil, mode: .status),
        HookEntry(event: "SessionEnd", matcher: nil, mode: .status),
    ])

    /// Cursor (editor and cursor-agent): risky shell commands and MCP tools are
    /// asked in the notch; everything else follows Cursor's own rules.
    static let cursor = HookTarget(id: "cursor", style: .flat, plan: [
        HookEntry(event: "beforeShellExecution", matcher: nil, mode: .waits),
        HookEntry(event: "beforeMCPExecution", matcher: nil, mode: .waits),
        HookEntry(event: "beforeSubmitPrompt", matcher: nil, mode: .status),
        HookEntry(event: "afterFileEdit", matcher: nil, mode: .status),
        HookEntry(event: "stop", matcher: nil, mode: .status),
    ])

    // Claude Code shorthands (kept for callers and tests).
    static let commandMarker = claudeCode.marker
    static var hookPlan: [HookEntry] { claudeCode.plan }

    /// The hook command. Status hooks add `status` and the reply hook `reply`,
    /// so a status copy of an event can never open a second request.
    static func command(executable: String, target: HookTarget = claudeCode, mode: HookMode = .waits) -> String {
        let quoted = "\"\(executable.replacingOccurrences(of: "\"", with: "\\\""))\" \(target.marker)"
        switch mode {
        case .waits: return quoted
        case .status: return quoted + " status"
        case .reply: return quoted + " reply"
        }
    }

    static func command(executable: String, waits: Bool) -> String {
        command(executable: executable, mode: waits ? .waits : .status)
    }

    private static func isOurs(_ handler: [String: Any], _ target: HookTarget) -> Bool {
        (handler["command"] as? String ?? "").contains(target.marker)
    }

    static func isInstalled(_ settings: [String: Any], target: HookTarget = claudeCode) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { entry in
                if isOurs(entry, target) { return true }  // flat style
                return (entry["hooks"] as? [[String: Any]] ?? []).contains { isOurs($0, target) }
            }
        }
    }

    /// Settings with this agent's NotchFlow hooks removed; everything else is kept.
    static func removing(from settings: [String: Any], target: HookTarget = claudeCode) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = entries.compactMap { entry in
                if entry["command"] != nil {  // flat style
                    return isOurs(entry, target) ? nil : entry
                }
                var entry = entry
                let handlers = (entry["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0, target) }
                guard !handlers.isEmpty else { return nil }
                entry["hooks"] = handlers
                return entry
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        if hooks.isEmpty {
            settings["hooks"] = nil
            if case .flat = target.style, Array(settings.keys) == ["version"] { settings["version"] = nil }
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    /// Settings with this agent's NotchFlow hooks added (replacing older ones).
    static func installing(into settings: [String: Any], executable: String, waitSeconds: Int,
                           target: HookTarget = claudeCode) -> [String: Any] {
        var settings = removing(from: settings, target: target)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for entry in target.plan {
            let command = command(executable: executable, target: target, mode: entry.mode)
            let item: [String: Any]
            switch target.style {
            case .flat:
                item = ["command": command]
            case .grouped(let backgroundFlag):
                var handler: [String: Any] = ["type": "command", "command": command]
                switch entry.mode {
                case .waits: handler["timeout"] = waitSeconds + 30
                case .status:
                    handler["timeout"] = 10
                    if backgroundFlag { handler["async"] = true }
                case .reply: handler["asyncRewake"] = true
                }
                var group: [String: Any] = ["hooks": [handler]]
                if let matcher = entry.matcher { group["matcher"] = matcher }
                item = group
            case .groupedMilliseconds:
                let handler: [String: Any] = ["type": "command", "command": command, "name": "notchflow",
                                              "timeout": entry.mode == .waits ? (waitSeconds + 30) * 1000 : 5000]
                var group: [String: Any] = ["hooks": [handler]]
                if let matcher = entry.matcher { group["matcher"] = matcher }
                item = group
            }
            var entries = hooks[entry.event] as? [[String: Any]] ?? []
            entries.append(item)
            hooks[entry.event] = entries
        }
        settings["hooks"] = hooks
        if case .flat = target.style, settings["version"] == nil { settings["version"] = 1 }
        return settings
    }

    // MARK: Cursor

    /// Turns a Cursor hook payload into the shared event shape: shell commands
    /// look like Bash, MCP calls like `mcp__<server>__<tool>`, edits like Edit.
    static func cursorEvent(from data: Data) -> AgentHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String else { return nil }
        let roots = object["workspace_roots"] as? [String] ?? []
        let cwd = (object["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? roots.first ?? ""
        var tool: String?
        var input: [String: Any] = [:]
        switch name {
        case "beforeShellExecution":
            tool = "Bash"
            input = ["command": object["command"] as? String ?? ""]
        case "beforeMCPExecution":
            let server = (object["server"] as? String) ?? (object["url"] as? String).flatMap { URL(string: $0)?.host } ?? "cursor"
            tool = "mcp__\(server)__\(object["tool_name"] as? String ?? "tool")"
            if let text = object["tool_input"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                input = parsed
            } else {
                input = object["tool_input"] as? [String: Any] ?? [:]
            }
        case "afterFileEdit":
            tool = "Edit"
            input = ["file_path": object["file_path"] as? String ?? ""]
        default:
            break
        }
        let status = object["status"] as? String
        return AgentHookEvent(
            name: name,
            sessionID: object["conversation_id"] as? String ?? "cursor",
            cwd: cwd,
            toolName: tool,
            toolInput: input,
            message: (object["prompt"] as? String) ?? status,
            notificationType: nil,
            detail: status,
            permissionSuggestions: []
        )
    }

    enum CursorPermission: String { case allow, deny, ask }

    static func cursorAnswer(_ permission: CursorPermission, userMessage: String? = nil, agentMessage: String? = nil) -> Data {
        var object: [String: Any] = ["permission": permission.rawValue]
        if let userMessage { object["user_message"] = userMessage }
        if let agentMessage { object["agent_message"] = agentMessage }
        return json(object)
    }

    // MARK: Gemini CLI

    static func geminiDeny(reason: String) -> Data { json(["decision": "deny", "reason": reason]) }

    // MARK: Replying from the notch (Claude Code)

    /// What Claude reads when it is woken with a reply typed in the notch.
    static func replyMessage(_ text: String) -> String {
        "The user replied from the NotchFlow notch: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    // MARK: Starting an agent in a terminal

    enum LaunchAgent: String, CaseIterable, Sendable {
        case claude, codex, gemini, cursor

        var title: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .gemini: return "Gemini CLI"
            case .cursor: return "Cursor Agent"
            }
        }

        /// The interactive command that starts the agent with a first prompt.
        fileprivate var invocation: String {
            switch self {
            case .claude: return "claude"
            case .codex: return "codex"
            case .gemini: return "gemini -i"
            case .cursor: return "cursor-agent"
            }
        }
    }

    /// Single-quotes a value for the shell (`'it'\''s'`).
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func launchCommand(agent: LaunchAgent, prompt: String, directory: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed.isEmpty ? agent.invocation.replacingOccurrences(of: " -i", with: "")
                                    : "\(agent.invocation) \(shellQuoted(trimmed))"
        return directory.isEmpty ? start : "cd \(shellQuoted(directory)) && \(start)"
    }

    enum TerminalApp: String, CaseIterable, Sendable {
        case terminal = "Terminal"
        case iTerm = "iTerm"

        var bundleID: String {
            switch self {
            case .terminal: return "com.apple.Terminal"
            case .iTerm: return "com.googlecode.iterm2"
            }
        }
    }

    /// AppleScript that opens a new window in the terminal and runs `command`.
    static func appleScript(running command: String, in terminal: TerminalApp) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch terminal {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        case .iTerm:
            return """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text "\(escaped)"
            end tell
            """
        }
    }

    // MARK: Helpers

    static func compactJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(400))
    }

    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// The first line of Claude's last message, for the "done" summary.
    static func summary(of message: String?) -> String {
        let firstLine = (message ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let cleaned = firstLine.replacingOccurrences(of: #"^[#*\-\s]+"#, with: "", options: .regularExpression)
        return cleaned.count > 120 ? String(cleaned.prefix(117)) + "…" : cleaned
    }
}
