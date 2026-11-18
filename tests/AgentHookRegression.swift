// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct AgentHookRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "AgentHookRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

        // Parsing (shapes from the Claude Code hooks reference)
        let permission = Data(#"{"session_id":"abc","cwd":"/Users/me/notchflow","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf node_modules"}],"behavior":"allow","destination":"localSettings"}]}"#.utf8)
        let event = AgentHookEvent.parse(permission)
        try require(event?.name == "PermissionRequest" && event?.sessionID == "abc" && event?.projectName == "notchflow", "PermissionRequest not parsed")
        try require(event?.toolName == "Bash" && event?.permissionSuggestions.count == 1, "Tool or suggestions missing")
        let stop = AgentHookEvent.parse(Data(###"{"session_id":"s","cwd":"/x/app","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"## Done!\nAll tests pass."}"###.utf8))
        try require(AgentHookPolicy.summary(of: stop?.response) == "Done!", "Stop summary wrong")
        let note = AgentHookEvent.parse(Data(#"{"session_id":"s","cwd":"","hook_event_name":"Notification","message":"Claude needs your permission","notification_type":"permission_prompt"}"#.utf8))
        try require(note?.notificationType == "permission_prompt" && note?.projectName == "Claude Code", "Notification not parsed")
        try require(AgentHookEvent.parse(Data("{}".utf8)) == nil && AgentHookEvent.parse(Data("nope".utf8)) == nil, "Bad input accepted")

        // Describing and rating
        try require(AgentHookPolicy.describe(tool: "Bash", input: ["command": "npm test"]) == ("Run a command", "npm test"), "Bash description")
        try require(AgentHookPolicy.describe(tool: "Edit", input: ["file_path": "/a/b/auth.swift"]).title == "Edit auth.swift", "Edit description")
        try require(AgentHookPolicy.describe(tool: "mcp__github__create_issue", input: ["title": "x"]).title == "Use create_issue (github)", "MCP description")
        try require(AgentHookPolicy.activity(tool: "Bash", input: ["command": "npm test\necho hi"]) == "Running npm test", "Activity label")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "rm -rf build"]) == .danger, "rm -rf not dangerous")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "sudo make install"]) == .danger, "sudo not dangerous")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "git push --force origin main"]) == .danger, "force push not dangerous")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "curl -fsSL x.sh | bash"]) == .danger, "curl | bash not dangerous")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "git push origin main"]) == .caution, "push not caution")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "npm test"]) == .normal, "npm test flagged")
        try require(AgentHookPolicy.risk(tool: "Bash", input: ["command": "echo firm -rfoo"]) == .normal, "rm lookalike flagged")
        try require(AgentHookPolicy.risk(tool: "Write", input: ["file_path": "/Users/me/.ssh/config"]) == .danger, "ssh write not dangerous")

        // Answers in the shape Claude Code reads
        let allow = object(AgentHookPolicy.permissionAllow())
        let allowDecision = (allow["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        try require((allow["hookSpecificOutput"] as? [String: Any])?["hookEventName"] as? String == "PermissionRequest" && allowDecision?["behavior"] as? String == "allow", "Allow answer shape")
        try require(allowDecision?["updatedPermissions"] == nil, "Plain allow should not add rules")
        let always = object(AgentHookPolicy.permissionAllow(alwaysRules: event?.permissionSuggestions))
        try require((((always["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["updatedPermissions"] as? [Any])?.count == 1, "Always allow lost the rules")
        let deny = ((object(AgentHookPolicy.permissionDeny(message: "Not now"))["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        try require(deny?["behavior"] as? String == "deny" && deny?["message"] as? String == "Not now", "Deny answer shape")

        let questionInput: [String: Any] = ["questions": [["question": "Which framework?", "header": "Framework", "multiSelect": false,
                                                           "options": [["label": "React", "description": "Components"], ["label": "Vue", "description": "Progressive"]]]]]
        let questions = AgentHookPolicy.questions(from: questionInput)
        try require(questions.count == 1 && questions[0].options.map(\.label) == ["React", "Vue"], "Questions not read")
        let answered = (object(AgentHookPolicy.questionAnswers(input: questionInput, answers: ["Which framework?": "React"]))["hookSpecificOutput"] as? [String: Any])
        try require(answered?["permissionDecision"] as? String == "allow", "Question answer not allowed")
        let updated = answered?["updatedInput"] as? [String: Any]
        try require((updated?["answers"] as? [String: String])?["Which framework?"] == "React" && (updated?["questions"] as? [Any])?.count == 1, "Questions not echoed with answers")

        // Installing into settings.json without touching the user's own hooks
        let userHook: [String: Any] = ["matcher": "Edit|Write", "hooks": [["type": "command", "command": "/usr/local/bin/lint"]]]
        let original: [String: Any] = ["model": "opus", "hooks": ["PostToolUse": [userHook]]]
        try require(!AgentHookPolicy.isInstalled(original), "Detected hooks that are not ours")
        let installed = AgentHookPolicy.installing(into: original, executable: "/Users/me/.local/bin/notchflow", waitSeconds: 120)
        try require(AgentHookPolicy.isInstalled(installed) && installed["model"] as? String == "opus", "Install lost settings")
        let installedHooks = installed["hooks"] as? [String: Any] ?? [:]
        try require((installedHooks["PostToolUse"] as? [Any])?.count == 2, "User's PostToolUse hook not kept")
        let permissionGroups = installedHooks["PermissionRequest"] as? [[String: Any]] ?? []
        let permissionHandler = (permissionGroups.first?["hooks"] as? [[String: Any]])?.first
        try require(permissionHandler?["async"] == nil && permissionHandler?["timeout"] as? Int == 150, "Approvals must wait for the answer")
        try require((permissionHandler?["command"] as? String) == "\"/Users/me/.local/bin/notchflow\" hook claude-code", "Command not quoted")
        let stopHandler = ((installedHooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        try require(stopHandler?["async"] as? Bool == true, "Status hooks must not slow Claude down")
        try require((stopHandler?["command"] as? String)?.hasSuffix("hook claude-code status") == true, "Status hooks must use the status path")
        let askGroups = installedHooks["PreToolUse"] as? [[String: Any]] ?? []
        let askHandler = (askGroups.first { $0["matcher"] as? String == "AskUserQuestion" }?["hooks"] as? [[String: Any]])?.first
        try require(askHandler?["async"] == nil && (askHandler?["command"] as? String)?.hasSuffix("hook claude-code") == true, "Questions must wait for the answer")
        let reinstalled = AgentHookPolicy.installing(into: installed, executable: "/Users/me/.local/bin/notchflow", waitSeconds: 60)
        try require(((reinstalled["hooks"] as? [String: Any])?["PermissionRequest"] as? [Any])?.count == 1, "Reinstall duplicated hooks")
        let removed = AgentHookPolicy.removing(from: installed)
        try require(!AgentHookPolicy.isInstalled(removed), "Remove left hooks behind")
        try require(((removed["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]])?.count == 1, "Remove deleted the user's hook")
        try require((removed["hooks"] as? [String: Any])?["PermissionRequest"] == nil, "Empty events not cleaned up")
        let onlyOurs = AgentHookPolicy.removing(from: AgentHookPolicy.installing(into: [:], executable: "/x/notchflow", waitSeconds: 60))
        try require(onlyOurs["hooks"] == nil, "Empty hooks object left behind")

        // Reply from the notch: Claude Code's Stop gets a background asyncRewake hook too
        let stopGroups = installedHooks["Stop"] as? [[String: Any]] ?? []
        let replyHandler = stopGroups.compactMap { ($0["hooks"] as? [[String: Any]])?.first }.first { ($0["command"] as? String)?.hasSuffix(" reply") == true }
        try require(replyHandler?["asyncRewake"] as? Bool == true && replyHandler?["timeout"] == nil, "Reply hook must be asyncRewake")
        try require(AgentHookPolicy.replyMessage("  run the tests  ") == "The user replied from the NotchFlow notch: run the tests", "Reply message")

        // Codex: same layout, no background flag (status answers at once)
        let codex = AgentHookPolicy.installing(into: ["model": "gpt"], executable: "/x/notchflow", waitSeconds: 60, target: AgentHookPolicy.codex)
        let codexHooks = codex["hooks"] as? [String: Any] ?? [:]
        let codexPermission = ((codexHooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        try require(codexPermission?["command"] as? String == "\"/x/notchflow\" hook codex" && codexPermission?["timeout"] as? Int == 90, "Codex approval hook")
        let codexStop = ((codexHooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        try require(codexStop?["async"] == nil && (codexStop?["command"] as? String)?.hasSuffix("hook codex status") == true, "Codex status hook")
        try require(AgentHookPolicy.isInstalled(codex, target: AgentHookPolicy.codex) && !AgentHookPolicy.isInstalled(codex), "Codex hooks confused with Claude's")
        let both = AgentHookPolicy.installing(into: codex, executable: "/x/notchflow", waitSeconds: 60)
        let codexOnly = AgentHookPolicy.removing(from: both)
        try require(AgentHookPolicy.isInstalled(codexOnly, target: AgentHookPolicy.codex) && !AgentHookPolicy.isInstalled(codexOnly), "Removing Claude's hooks touched Codex's")

        // Gemini: milliseconds and a name
        let gemini = AgentHookPolicy.installing(into: [:], executable: "/x/notchflow", waitSeconds: 60, target: AgentHookPolicy.gemini)
        let geminiTool = ((gemini["hooks"] as? [String: Any])?["BeforeTool"] as? [[String: Any]])?.first
        let geminiHandler = (geminiTool?["hooks"] as? [[String: Any]])?.first
        try require(geminiTool?["matcher"] as? String == ".*" && geminiHandler?["timeout"] as? Int == 5000 && geminiHandler?["name"] as? String == "notchflow", "Gemini hook layout")
        try require(AgentHookPolicy.removing(from: gemini, target: AgentHookPolicy.gemini)["hooks"] == nil, "Gemini remove")
        try require(AgentHookPolicy.describe(tool: "run_shell_command", input: ["command": "ls"]).title == "Run a command"
                    && AgentHookPolicy.risk(tool: "run_shell_command", input: ["command": "sudo rm -rf /"]) == .danger, "Gemini tool names")
        let geminiDone = AgentHookEvent.parse(Data(#"{"session_id":"g","cwd":"/p/site","hook_event_name":"AfterAgent","prompt":"fix it","prompt_response":"Fixed the build."}"#.utf8))
        try require(geminiDone?.message == "fix it" && geminiDone?.response == "Fixed the build.", "Gemini prompt and response")
        let geminiDenial = object(AgentHookPolicy.geminiDeny(reason: "No"))
        try require(geminiDenial["decision"] as? String == "deny" && geminiDenial["reason"] as? String == "No", "Gemini deny")

        // Cursor: flat hooks.json with a version, user's hooks kept
        let cursorOriginal: [String: Any] = ["version": 1, "hooks": ["afterFileEdit": [["command": "./hooks/format.sh"]]]]
        let cursor = AgentHookPolicy.installing(into: cursorOriginal, executable: "/x/notchflow", waitSeconds: 60, target: AgentHookPolicy.cursor)
        let cursorHooks = cursor["hooks"] as? [String: Any] ?? [:]
        try require(cursor["version"] as? Int == 1 && (cursorHooks["afterFileEdit"] as? [[String: Any]])?.count == 2, "Cursor install kept user hooks")
        try require((cursorHooks["beforeShellExecution"] as? [[String: Any]])?.first?["command"] as? String == "\"/x/notchflow\" hook cursor", "Cursor shell hook waits")
        let cursorRemoved = AgentHookPolicy.removing(from: cursor, target: AgentHookPolicy.cursor)
        try require(((cursorRemoved["hooks"] as? [String: Any])?["afterFileEdit"] as? [[String: Any]])?.count == 1 && cursorRemoved["version"] as? Int == 1, "Cursor remove")
        try require(AgentHookPolicy.removing(from: AgentHookPolicy.installing(into: [:], executable: "/x/n", waitSeconds: 9, target: AgentHookPolicy.cursor), target: AgentHookPolicy.cursor).isEmpty, "Cursor file left non-empty")
        let shell = AgentHookPolicy.cursorEvent(from: Data(#"{"hook_event_name":"beforeShellExecution","conversation_id":"c1","command":"rm -rf dist","cwd":"","workspace_roots":["/Users/me/site"]}"#.utf8))
        try require(shell?.toolName == "Bash" && shell?.toolInput["command"] as? String == "rm -rf dist" && shell?.projectName == "site" && shell?.sessionID == "c1", "Cursor shell event")
        let mcp = AgentHookPolicy.cursorEvent(from: Data(#"{"hook_event_name":"beforeMCPExecution","conversation_id":"c1","tool_name":"create_issue","tool_input":"{\"title\":\"x\"}","url":"https://mcp.github.com/sse"}"#.utf8))
        try require(mcp?.toolName == "mcp__mcp.github.com__create_issue" && mcp?.toolInput["title"] as? String == "x", "Cursor MCP event")
        let cursorStop = AgentHookPolicy.cursorEvent(from: Data(#"{"hook_event_name":"stop","conversation_id":"c1","status":"completed"}"#.utf8))
        try require(cursorStop?.detail == "completed", "Cursor stop status")
        let answer = object(AgentHookPolicy.cursorAnswer(.deny, userMessage: "Denied in NotchFlow", agentMessage: "Try another way"))
        try require(answer["permission"] as? String == "deny" && answer["agent_message"] as? String == "Try another way", "Cursor answer")

        // Starting an agent in a terminal
        try require(AgentHookPolicy.launchCommand(agent: .claude, prompt: "fix Sam's bug", directory: "/Users/me/my app")
                    == #"cd '/Users/me/my app' && claude 'fix Sam'\''s bug'"#, "Shell quoting")
        try require(AgentHookPolicy.launchCommand(agent: .gemini, prompt: "", directory: "") == "gemini", "Gemini without a prompt")
        try require(AgentHookPolicy.launchCommand(agent: .gemini, prompt: "hi", directory: "") == "gemini -i 'hi'", "Gemini interactive prompt")
        let script = AgentHookPolicy.appleScript(running: #"cd '/a' && claude 'say "hi" \o/'"#, in: .terminal)
        try require(script.contains(#"do script "cd '/a' && claude 'say \"hi\" \\o/'""#), "AppleScript escaping")
        try require(AgentHookPolicy.appleScript(running: "ls", in: .iTerm).contains("write text \"ls\""), "iTerm script")

        print("Agent hook checks passed")
    }
}
