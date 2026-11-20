// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct AIRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "AIRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = AIProviderPolicy

        // Providers
        for provider in AIProvider.allCases where provider != .custom {
            try require(URL(string: provider.defaultBaseURL) != nil && !provider.defaultModel.isEmpty, "\(provider) defaults")
        }
        let openAI = try P.request(provider: .openAI, baseURL: "https://api.openai.com/v1/", model: "gpt-4.1-mini", key: " sk-1 ",
                                   system: "S", user: "U", maxTokens: 300)
        try require(openAI.url.absoluteString == "https://api.openai.com/v1/chat/completions", "OpenAI URL \(openAI.url)")
        try require(openAI.headers["Authorization"] == "Bearer sk-1", "OpenAI auth")
        try require(openAI.body["max_completion_tokens"] as? Int == 300 && openAI.body["temperature"] == nil, "OpenAI token field")
        try require((openAI.body["messages"] as? [[String: String]])?.map { $0["role"]! } == ["system", "user"], "OpenAI messages")
        _ = try JSONSerialization.data(withJSONObject: openAI.body)

        let claude = try P.request(provider: .anthropic, baseURL: AIProvider.anthropic.defaultBaseURL, model: "claude-opus-5-5",
                                   key: "k", system: "S", user: "U", maxTokens: 600)
        try require(claude.url.absoluteString == "https://api.anthropic.com/v1/messages", "Claude URL")
        try require(claude.headers["x-api-key"] == "k" && claude.headers["anthropic-version"] == "2026-10-21"
                    && claude.headers["Authorization"] == nil, "Claude headers")
        try require(claude.body["system"] as? String == "S" && claude.body["temperature"] == nil, "Claude body")
        try require((claude.body["output_config"] as? [String: String])?["effort"] == "low", "Claude effort")
        try require(claude.body["fallbacks"] as? String == "default" && claude.headers["anthropic-beta"] != nil, "Claude fallbacks")
        let haiku = try P.request(provider: .anthropic, baseURL: AIProvider.anthropic.defaultBaseURL, model: "claude-haiku-5-5",
                                  key: "k", system: "S", user: "U", maxTokens: 600)
        try require(haiku.body["fallbacks"] == nil && haiku.headers["anthropic-beta"] == nil, "Fallbacks sent for Haiku")
        _ = try JSONSerialization.data(withJSONObject: claude.body)

        let local = try P.request(provider: .ollama, baseURL: AIProvider.ollama.defaultBaseURL, model: "llama3.2", key: nil,
                                  system: "S", user: "U", maxTokens: 300)
        try require(local.headers["Authorization"] == nil && local.body["max_tokens"] as? Int == 300, "Local server")
        do { _ = try P.request(provider: .groq, baseURL: AIProvider.groq.defaultBaseURL, model: "m", key: "", system: "", user: "", maxTokens: 1)
             try require(false, "No key accepted") } catch P.Problem.noKey {}
        do { _ = try P.request(provider: .custom, baseURL: "not a url", model: "m", key: nil, system: "", user: "", maxTokens: 1)
             try require(false, "Bad URL accepted") } catch P.Problem.badURL {}

        // Responses
        let claudeAnswer = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"[\"Haan, pakka!\"]"}],"stop_reason":"end_turn"}"#
        try require(P.text(fromResponse: Data(claudeAnswer.utf8), format: .anthropic) == #"["Haan, pakka!"]"#, "Claude text")
        let openAIAnswer = #"{"choices":[{"message":{"content":"<think>hmm</think> Hello"}}]}"#
        try require(P.text(fromResponse: Data(openAIAnswer.utf8), format: .openAI) == "Hello", "OpenAI text")
        try require(P.errorMessage(in: Data(#"{"error":{"message":"Invalid key"}}"#.utf8)) == "Invalid key", "Error message")
        try require(P.errorMessage(in: Data(#"{"base_resp":{"status_code":1004,"status_msg":"auth failed"}}"#.utf8)) == "auth failed", "MiniMax error")

        // Promises in any language: what's worth asking about
        typealias A = PromiseAIPolicy
        for text in ["main kal shaam tak bhej dunga", "Kal call karti hu", "hu kale moklish", "હું સાંજે ફોન કરીશ",
                     "मी उद्या पाठवतो", "मैं कल भेज दूंगा", "Done, will send it by 5", "Bas 2 ghante mein aata hu"] {
            try require(A.mightBePromise(text), "Missed: \(text)")
        }
        for text in ["ok", "haha", "Kya haal hai?", "Thanks bro", "😂😂", "nice pic", "local train is late"] {
            try require(!A.mightBePromise(text), "Would send small talk: \(text)")
        }

        // Asking and reading the answer
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14, minute: 5))!
        let messages = [PromiseAIMessage(id: 1, text: "main kal shaam tak bhej dunga", fromMe: true, person: "Sam"),
                        PromiseAIMessage(id: 2, text: "hu kale call karish", fromMe: false, person: "Riya"),
                        PromiseAIMessage(id: 3, text: "kal kya plan hai?", fromMe: false, person: "Riya")]
        let prompt = A.userPrompt(messages, now: now, calendar: calendar)
        try require(prompt.contains("Now: Friday 2026-11-20T14:05") && prompt.contains("[1] Me to Sam: main kal")
                    && prompt.contains("[2] Riya to me:"), "Prompt: \(prompt)")
        let answer = """
        Here you go:
        ```json
        [{"id": 1, "task": "send Sam the file.", "due": "2026-11-21T19:00"},
         {"id": "2", "task": "Call me", "due": null},
         {"id": 1, "task": "duplicate", "due": null},
         {"id": 9, "task": "unknown message", "due": null},
         {"id": 3, "task": "x", "due": "2026-11-19T10:00"}]
        ```
        """
        let found = A.promises(fromAnswer: answer, messages: messages, now: now, calendar: calendar)
        try require(found.map(\.messageID) == [1, 2], "Promises found: \(found.map(\.messageID))")
        try require(found[0].candidate.title == "Send Sam the file" && found[0].candidate.kind == .mine
                    && found[0].candidate.hasExplicitTime, "First promise: \(found[0].candidate)")
        try require(calendar.component(.hour, from: found[0].candidate.due) == 19
                    && calendar.component(.day, from: found[0].candidate.due) == 21, "Due time")
        try require(found[1].candidate.kind == .theirs && !found[1].candidate.hasExplicitTime
                    && found[1].candidate.due == now.addingTimeInterval(86_400), "Second promise")
        let past = A.promises(fromAnswer: #"[{"id":1,"task":"Send it","due":"2026-11-19T10:00"}]"#, messages: messages, now: now, calendar: calendar)
        try require(past.first?.candidate.due == now.addingTimeInterval(3600), "Past due time not moved forward")
        try require(A.promises(fromAnswer: "[]", messages: messages, now: now, calendar: calendar).isEmpty
                    && A.promises(fromAnswer: "No promises here.", messages: messages, now: now, calendar: calendar).isEmpty, "Empty answers")
        print("AI providers and any-language promises: OK")
    }
}
