// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct AgentTranscriptRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "AgentTranscriptRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let claude = """
        {"type":"summary","summary":"Fix tests"}
        {"type":"user","uuid":"u1","sessionId":"s-1","cwd":"/Users/me/notchflow","timestamp":"2026-11-18T10:00:00.000Z","message":{"role":"user","content":"Fix the failing tests"}}
        {"type":"user","uuid":"u0","isMeta":true,"message":{"role":"user","content":"<command-name>/clear</command-name>"}}
        {"type":"assistant","uuid":"a1","timestamp":"2026-11-18T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Running the tests first."},{"type":"tool_use","name":"Bash","input":{"command":"npm test\\necho done"}},{"type":"tool_use","name":"Edit","input":{"file_path":"/x/auth.swift"}},{"type":"tool_use","name":"TodoWrite","input":{}}]}}
        {"type":"user","uuid":"u2","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
        {"type":"assistant","uuid":"side","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent"}]}}
        not json
        {"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass."}]}}
        """
        let items = AgentTranscriptPolicy.claudeItems(from: Data(claude.utf8))
        try require(items.map(\.role) == [.user, .assistant, .tool, .tool, .assistant], "Claude roles: \(items.map(\.role))")
        try require(items[0].text == "Fix the failing tests" && items[0].date != nil, "Claude user message")
        try require(items[2].text == "Ran npm test" && items[3].text == "Edit auth.swift", "Claude tool lines: \(items[2].text) / \(items[3].text)")
        let claudeSummary = AgentTranscriptPolicy.claudeSummary(from: Data(claude.utf8), fileURL: URL(fileURLWithPath: "/t/s-1.jsonl"), modified: Date())
        try require(claudeSummary?.id == "s-1" && claudeSummary?.project == "notchflow" && claudeSummary?.title == "Fix the failing tests", "Claude summary")

        let codex = """
        {"timestamp":"2026-11-18T09:00:00.000Z","type":"session_meta","payload":{"id":"0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b","cwd":"/Users/me/anti-gravity","cli_version":"0.150.0"}}
        {"timestamp":"2026-11-18T09:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}
        {"timestamp":"2026-11-18T09:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Add a physics loop"}]}}
        {"timestamp":"2026-11-18T09:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"swift build\\"]}","call_id":"c1"}}
        {"timestamp":"2026-11-18T09:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"ok"}}
        {"timestamp":"2026-11-18T09:00:05.000Z","type":"event_msg","payload":{"type":"agent_message","message":"dup"}}
        {"timestamp":"2026-11-18T09:00:06.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Added the loop."}]}}
        """
        let codexItems = AgentTranscriptPolicy.codexItems(from: Data(codex.utf8))
        try require(codexItems.map(\.role) == [.user, .tool, .assistant], "Codex roles: \(codexItems.map(\.role))")
        try require(codexItems[1].text == "Ran swift build" && codexItems[2].text == "Added the loop.", "Codex text: \(codexItems.map(\.text))")
        let codexSummary = AgentTranscriptPolicy.codexSummary(from: Data(codex.utf8), fileURL: URL(fileURLWithPath: "/t/rollout-x.jsonl"), modified: Date())
        try require(codexSummary?.id == "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b" && codexSummary?.project == "anti-gravity" && codexSummary?.title == "Add a physics loop", "Codex summary")
        try require(AgentTranscriptPolicy.codexID(fromFileName: "rollout-2026-11-18T10-00-00-0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jsonl") == "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b", "Codex id from file name")

        // Commands
        try require(AgentTranscriptPolicy.continueCommand(agent: .claude, sessionID: "s-1", message: "and the lint")
                    == "claude -p --resume 's-1' --output-format stream-json --verbose 'and the lint'", "Claude continue command")
        try require(AgentTranscriptPolicy.continueCommand(agent: .codex, sessionID: "abc", message: "it's fine")
                    == #"codex exec --json resume 'abc' 'it'\''s fine'"#, "Codex continue command")
        try require(AgentTranscriptPolicy.startCommand(agent: .codex, message: "hi") == "codex exec --json 'hi'", "Codex start")
        let shell = AgentTranscriptPolicy.shellInvocation("claude -p 'x'")
        try require(shell[0] == "-l" && shell[2].hasSuffix("claude -p 'x'") && shell[2].contains("/opt/homebrew/bin"), "Login shell with PATH")

        // Streamed output
        try require(AgentTranscriptPolicy.sessionID(fromStreamLine: #"{"type":"system","subtype":"init","session_id":"s-9"}"#) == "s-9", "Claude init id")
        try require(AgentTranscriptPolicy.sessionID(fromStreamLine: #"{"type":"thread.started","thread_id":"t-1"}"#) == "t-1", "Codex thread id")
        try require(AgentTranscriptPolicy.sessionID(fromStreamLine: "zsh: command not found") == nil, "Noise read as an id")
        try require(AgentTranscriptPolicy.failure(fromStreamLine: #"{"type":"result","is_error":true,"result":"Credit balance too low"}"#) == "Credit balance too low", "Claude failure")
        try require(AgentTranscriptPolicy.failure(fromStreamLine: #"{"type":"result","is_error":false,"result":"ok"}"#) == nil, "Success read as failure")
        try require(AgentTranscriptPolicy.failure(fromStreamLine: #"{"type":"turn.failed","error":{"message":"rate limited"}}"#) == "rate limited", "Codex failure")

        // Turn end from the transcript tail (no Stop hook)

        let interruptedTail = Data(#"""

        partial line without json

        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}

        {"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}

        """#.utf8)

        guard AgentTranscriptPolicy.claudeTurnEnd(fromTail: interruptedTail) == .interrupted else { fatalError("Interrupted") }

        let answeredTail = Data(#"""

        {"type":"user","message":{"content":"fix it"}}

        {"type":"assistant","message":{"content":[{"type":"text","text":"Done.\nAll fixed."}]}}

        {"type":"system","content":"x"}

        """#.utf8)

        guard case .answered(let answer)? = AgentTranscriptPolicy.claudeTurnEnd(fromTail: answeredTail), answer.hasPrefix("Done.") else { fatalError("Answered") }

        let toolTail = Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Let me run it"},{"type":"tool_use","name":"Bash","input":{}}]}}"#.utf8)

        guard AgentTranscriptPolicy.claudeTurnEnd(fromTail: toolTail) == nil else { fatalError("Tool pending") }

        let promptTail = Data(#"{"type":"user","message":{"content":"go"}}"#.utf8)

        guard AgentTranscriptPolicy.claudeTurnEnd(fromTail: promptTail) == nil else { fatalError("Prompt pending") }

        print("Agent transcript checks passed")
    }
}
