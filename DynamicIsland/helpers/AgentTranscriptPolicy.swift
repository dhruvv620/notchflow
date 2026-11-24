// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Pure logic for showing and continuing agent conversations in the notch
// (Foundation only, so Build.command can check it alone):
// - reading Claude Code transcripts (~/.claude/projects/<dir>/<session>.jsonl)
//   and Codex rollouts (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl) into chat items;
// - building the headless commands that continue or start a session;
// - reading the session id from their streamed output.
//
// Neither file format is formally documented and both change between
// releases, so every reader skips lines it does not understand.

struct AgentChatItem: Equatable, Sendable, Identifiable {
    enum Role: String, Sendable {
        case user, assistant, tool
    }

    let id: String
    let role: Role
    let text: String
    let date: Date?
}

struct AgentSessionSummary: Equatable, Sendable, Identifiable {
    enum Agent: String, Sendable { case claude, codex }

    let id: String
    let agent: Agent
    let cwd: String
    /// The first thing the user asked, as the session's title.
    let title: String
    let updatedAt: Date
    let fileURL: URL

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Home" : name
    }
}

enum AgentTranscriptPolicy {
    // MARK: Reading

    static func lines(_ data: Data) -> [[String: Any]] {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return isoWithFraction.date(from: text) ?? iso.date(from: text)
    }

    /// Text the tools inject into the user's turn, which is not something the user typed.
    static func isInjected(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["<environment_context", "<user_instructions", "<command-name>", "<command-message>",
                        "<local-command-stdout>", "<system-reminder>", "Caveat: The messages below", "[Request interrupted"]
        return trimmed.isEmpty || prefixes.contains { trimmed.hasPrefix($0) }
    }

    /// One line describing a tool call ("Ran npm test", "Edited auth.swift").
    static func toolLine(name: String, input: [String: Any]) -> String {
        let (title, detail) = AgentHookPolicy.describe(tool: name, input: input)
        let first = detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        switch name {
        case "Bash", "shell", "local_shell", "exec_command", "run_shell_command":
            return first.isEmpty ? "Ran a command" : "Ran \(first.prefix(120))"
        default:
            return title
        }
    }

    // MARK: Claude Code

    static func claudeItems(from data: Data) -> [AgentChatItem] {
        var items: [AgentChatItem] = []
        for (index, line) in lines(data).enumerated() {
            guard let type = line["type"] as? String, type == "user" || type == "assistant",
                  line["isSidechain"] as? Bool != true, line["isMeta"] as? Bool != true,
                  let message = line["message"] as? [String: Any] else { continue }
            let id = line["uuid"] as? String ?? "c\(index)"
            let when = date(line["timestamp"])
            if let text = message["content"] as? String {
                guard !isInjected(text) else { continue }
                items.append(AgentChatItem(id: id, role: type == "user" ? .user : .assistant, text: text, date: when))
                continue
            }
            for (blockIndex, block) in (message["content"] as? [[String: Any]] ?? []).enumerated() {
                let blockID = "\(id)-\(blockIndex)"
                switch block["type"] as? String {
                case "text":
                    let text = block["text"] as? String ?? ""
                    guard !isInjected(text) else { continue }
                    items.append(AgentChatItem(id: blockID, role: type == "user" ? .user : .assistant, text: text, date: when))
                case "tool_use":
                    let name = block["name"] as? String ?? "tool"
                    guard name != "TodoWrite" else { continue }
                    items.append(AgentChatItem(id: blockID, role: .tool,
                                               text: toolLine(name: name, input: block["input"] as? [String: Any] ?? [:]), date: when))
                default:
                    continue  // tool results and thinking stay in the terminal
                }
            }
        }
        return items
    }

    /// How a Claude Code turn ended, read from the end of its transcript, for
    /// when no Stop hook came (Esc interrupts never send one).
    enum TurnEnd: Equatable {
        case interrupted
        /// The last thing written is Claude's answer (text, no tool call pending).
        case answered(String)
    }

    static func claudeTurnEnd(fromTail data: Data) -> TurnEnd? {
        // The tail may start mid-line; lines() skips what doesn't parse.
        for line in lines(data).reversed() {
            guard let type = line["type"] as? String, type == "user" || type == "assistant",
                  line["isSidechain"] as? Bool != true,
                  let message = line["message"] as? [String: Any] else { continue }
            let blocks = message["content"] as? [[String: Any]] ?? []
            let texts = (message["content"] as? String).map { [$0] } ?? blocks.compactMap { $0["text"] as? String }
            if type == "user" {
                if texts.contains(where: { $0.contains("[Request interrupted by user") }) { return .interrupted }
                return nil  // a prompt or tool result: Claude is still on it
            }
            if blocks.contains(where: { $0["type"] as? String == "tool_use" }) { return nil }
            guard let last = texts.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            return .answered(oneLine(last))
        }
        return nil
    }

    /// Session id, folder, title and last activity, from a transcript's lines.
    static func claudeSummary(from data: Data, fileURL: URL, modified: Date) -> AgentSessionSummary? {
        let all = lines(data)
        let id = all.lazy.compactMap { $0["sessionId"] as? String }.first ?? fileURL.deletingPathExtension().lastPathComponent
        let cwd = all.lazy.compactMap { $0["cwd"] as? String }.first ?? ""
        let title = claudeItems(from: data).first { $0.role == .user }?.text ?? ""
        guard !title.isEmpty else { return nil }
        return AgentSessionSummary(id: id, agent: .claude, cwd: cwd, title: oneLine(title), updatedAt: modified, fileURL: fileURL)
    }

    // MARK: Codex

    static func codexItems(from data: Data) -> [AgentChatItem] {
        var items: [AgentChatItem] = []
        for (index, line) in lines(data).enumerated() {
            guard line["type"] as? String == "response_item", let payload = line["payload"] as? [String: Any] else { continue }
            let when = date(line["timestamp"])
            let id = "x\(index)"
            switch payload["type"] as? String {
            case "message":
                let role = payload["role"] as? String
                guard role == "user" || role == "assistant" else { continue }
                let text = (payload["content"] as? [[String: Any]] ?? [])
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                guard !isInjected(text) else { continue }
                items.append(AgentChatItem(id: id, role: role == "user" ? .user : .assistant, text: text, date: when))
            case "function_call", "custom_tool_call", "local_shell_call":
                let name = payload["name"] as? String ?? "shell"
                var input: [String: Any] = [:]
                if let arguments = payload["arguments"] as? String,
                   let parsed = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] {
                    input = parsed
                } else if let action = payload["action"] as? [String: Any] {
                    input = action
                }
                if let command = input["command"] as? [String] {
                    // ["bash", "-lc", "npm test"] → "npm test"
                    input["command"] = command.count >= 3 && command[1] == "-lc" ? command[2] : command.joined(separator: " ")
                }
                let tool = ["shell", "local_shell", "exec_command", "local_shell_call"].contains(name) || payload["type"] as? String == "local_shell_call" ? "Bash" : name
                items.append(AgentChatItem(id: id, role: .tool, text: toolLine(name: tool, input: input), date: when))
            default:
                continue
            }
        }
        return items
    }

    static func codexSummary(from data: Data, fileURL: URL, modified: Date) -> AgentSessionSummary? {
        let all = lines(data)
        let meta = all.first { $0["type"] as? String == "session_meta" }?["payload"] as? [String: Any]
        guard let id = meta?["id"] as? String ?? codexID(fromFileName: fileURL.lastPathComponent) else { return nil }
        // Codex writes long instructions first: the first message can be past
        // the part read here, or not written yet. The session still counts.
        let title = codexItems(from: data).first { $0.role == .user }?.text ?? ""
        guard meta != nil || !title.isEmpty else { return nil }
        return AgentSessionSummary(id: id, agent: .codex, cwd: meta?["cwd"] as? String ?? "",
                                   title: title.isEmpty ? "Codex session" : oneLine(title),
                                   updatedAt: modified, fileURL: fileURL)
    }

    /// rollout-2026-11-18T10-00-00-<uuid>.jsonl → <uuid>
    static func codexID(fromFileName name: String) -> String? {
        guard let match = name.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
                                     options: .regularExpression) else { return nil }
        return String(name[match])
    }

    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 90 ? String(trimmed.prefix(87)) + "…" : trimmed
    }

    // MARK: Continuing and starting sessions without a terminal

    /// The shell command that sends `message` to an existing session and runs
    /// it to the end of the turn, printing JSON events.
    static func continueCommand(agent: AgentSessionSummary.Agent, sessionID: String, message: String) -> String {
        let q = AgentHookPolicy.shellQuoted
        switch agent {
        case .claude:
            return "claude -p --resume \(q(sessionID)) --output-format stream-json --verbose \(q(message))"
        case .codex:
            return "codex exec --json resume \(q(sessionID)) \(q(message))"
        }
    }

    static func startCommand(agent: AgentSessionSummary.Agent, message: String) -> String {
        let q = AgentHookPolicy.shellQuoted
        switch agent {
        case .claude: return "claude -p --output-format stream-json --verbose \(q(message))"
        case .codex: return "codex exec --json \(q(message))"
        }
    }

    /// GUI apps don't get the user's shell PATH, so the command runs in a
    /// login shell with the usual install folders added.
    static func shellInvocation(_ command: String) -> [String] {
        let path = "export PATH=\"$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; "
        return ["-l", "-c", path + command]
    }

    /// The session id announced on a streamed line, if any (Claude's init
    /// event, Codex's thread.started).
    static func sessionID(fromStreamLine line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        if object["type"] as? String == "system", let id = object["session_id"] as? String { return id }
        if object["type"] as? String == "thread.started", let id = object["thread_id"] as? String { return id }
        return nil
    }

    /// An error message on a streamed line, if the run failed.
    static func failure(fromStreamLine line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        if object["type"] as? String == "result", object["is_error"] as? Bool == true {
            return object["result"] as? String ?? "The agent stopped with an error."
        }
        if object["type"] as? String == "turn.failed" || object["type"] as? String == "error" {
            return ((object["error"] as? [String: Any])?["message"] as? String) ?? object["message"] as? String ?? "The agent stopped with an error."
        }
        return nil
    }
}
