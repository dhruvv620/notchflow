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
    /// Notification text, the submitted prompt, or Claude's last message (Stop).
    let message: String?
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
        let message = (object["message"] as? String)
            ?? (object["prompt"] as? String)
            ?? (object["last_assistant_message"] as? String)
        return AgentHookEvent(
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
        case "Bash": return ("Run a command", string("command"))
        case "Edit", "MultiEdit": return ("Edit \(file("file_path"))", string("file_path"))
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
        case "Bash": return shortDetail.isEmpty ? "Running a command" : "Running \(shortDetail)"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing \((detail as NSString).lastPathComponent)"
        case "Read": return "Reading \((detail as NSString).lastPathComponent)"
        case "Grep", "Glob": return "Searching the code"
        case "WebFetch", "WebSearch": return "Looking things up"
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
        if tool == "Bash" {
            let command = (input["command"] as? String ?? "").lowercased()
            if dangerousPatterns.contains(where: { command.range(of: $0, options: .regularExpression) != nil }) { return .danger }
            if cautionPatterns.contains(where: { command.range(of: $0, options: .regularExpression) != nil }) { return .caution }
            return .normal
        }
        if ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(tool) {
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

    // MARK: Installing into ~/.claude/settings.json

    /// Every NotchFlow hook command contains this, which is how they are found again.
    static let commandMarker = "hook claude-code"

    /// Events NotchFlow listens to, and whether Claude Code waits for the answer.
    /// Only approvals and questions wait; status updates run in the background.
    static let hookPlan: [(event: String, matcher: String?, waits: Bool)] = [
        ("PermissionRequest", nil, true),
        ("PreToolUse", "AskUserQuestion", true),
        ("PreToolUse", "*", false),
        ("PostToolUse", "*", false),
        ("Notification", nil, false),
        ("UserPromptSubmit", nil, false),
        ("Stop", nil, false),
        ("SessionStart", nil, false),
        ("SessionEnd", nil, false),
    ]

    /// The hook command. Background (status) hooks add `status`, so a status
    /// copy of an event can never open a second approval or question.
    static func command(executable: String, waits: Bool = true) -> String {
        let quoted = "\"\(executable.replacingOccurrences(of: "\"", with: "\\\""))\" \(commandMarker)"
        return waits ? quoted : quoted + " status"
    }

    static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains(commandMarker) }
            }
        }
    }

    /// Settings with NotchFlow's hooks removed; everything else is kept as it was.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                var group = group
                let handlers = (group["hooks"] as? [[String: Any]] ?? [])
                    .filter { !($0["command"] as? String ?? "").contains(commandMarker) }
                guard !handlers.isEmpty else { return nil }
                group["hooks"] = handlers
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// Settings with NotchFlow's hooks added (replacing any older NotchFlow hooks).
    static func installing(into settings: [String: Any], executable: String, waitSeconds: Int) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for entry in hookPlan {
            var handler: [String: Any] = ["type": "command", "command": command(executable: executable, waits: entry.waits)]
            if entry.waits {
                handler["timeout"] = waitSeconds + 30
            } else {
                handler["async"] = true
                handler["timeout"] = 10
            }
            var group: [String: Any] = ["hooks": [handler]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            var groups = hooks[entry.event] as? [[String: Any]] ?? []
            groups.append(group)
            hooks[entry.event] = groups
        }
        settings["hooks"] = hooks
        return settings
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
