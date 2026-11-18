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
        try require(AgentHookPolicy.summary(of: stop?.message) == "Done!", "Stop summary wrong")
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

        print("Agent hook checks passed")
    }
}
