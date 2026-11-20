// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// An AI service NotchFlow can ask, with the user's own key. Most speak the
/// OpenAI chat-completions format; Claude has its own.
enum AIProvider: String, CaseIterable, Codable, Sendable {
    case minimax, openAI, anthropic, gemini, groq, openRouter, deepSeek, mistral, xAI, together, ollama, lmStudio, custom

    enum Format: Sendable { case openAI, anthropic }

    var title: String {
        switch self {
        case .minimax: return "MiniMax"
        case .openAI: return "OpenAI (ChatGPT)"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google Gemini"
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter (hundreds of models)"
        case .deepSeek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .xAI: return "xAI (Grok)"
        case .together: return "Together AI"
        case .ollama: return "Ollama (on this Mac)"
        case .lmStudio: return "LM Studio (on this Mac)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var format: Format { self == .anthropic ? .anthropic : .openAI }

    var defaultBaseURL: String {
        switch self {
        case .minimax: return "https://api.minimax.io/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .xAI: return "https://api.x.ai/v1"
        case .together: return "https://api.together.xyz/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .minimax: return "MiniMax-M2"
        case .openAI: return "gpt-4.1-mini"
        case .anthropic: return "claude-opus-5-5"
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .openRouter: return "openai/gpt-4.1-mini"
        case .deepSeek: return "deepseek-chat"
        case .mistral: return "mistral-small-latest"
        case .xAI: return "grok-3-mini"
        case .together: return "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .ollama: return "llama3.2"
        case .lmStudio: return "local-model"
        case .custom: return ""
        }
    }

    /// Where to get a key.
    var keyPage: String? {
        switch self {
        case .minimax: return "https://platform.minimax.io/user-center/basic-information/interface-key"
        case .openAI: return "https://platform.openai.com/api-keys"
        case .anthropic: return "https://platform.claude.com/settings/keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .groq: return "https://console.groq.com/keys"
        case .openRouter: return "https://openrouter.ai/settings/keys"
        case .deepSeek: return "https://platform.deepseek.com/api_keys"
        case .mistral: return "https://console.mistral.ai/api-keys"
        case .xAI: return "https://console.x.ai"
        case .together: return "https://api.together.ai/settings/api-keys"
        case .ollama, .lmStudio, .custom: return nil
        }
    }

    /// Local servers run without a key; a custom server may or may not need one.
    var needsKey: Bool { !(self == .ollama || self == .lmStudio || self == .custom) }
    var runsOnThisMac: Bool { self == .ollama || self == .lmStudio }
}

/// One request, ready to send (no URLSession here, so tests run anywhere).
struct AIRequest {
    let url: URL
    let headers: [String: String]
    let body: [String: Any]
}

enum AIProviderPolicy {
    enum Problem: Error, Equatable { case noKey, badURL, noModel }

    /// Builds the request for a system and user prompt.
    static func request(provider: AIProvider, baseURL: String, model: String, key: String?,
                        system: String, user: String, maxTokens: Int) throws -> AIRequest {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !model.isEmpty else { throw Problem.noModel }
        if provider.needsKey && key == nil { throw Problem.noKey }

        switch provider.format {
        case .anthropic:
            guard let url = URL(string: base + "/messages"), url.scheme?.hasPrefix("http") == true else { throw Problem.badURL }
            var headers = ["Content-Type": "application/json", "anthropic-version": "2026-10-21"]
            if let key { headers["x-api-key"] = key }
            var body: [String: Any] = [
                "model": model,
                "max_tokens": max(maxTokens, 2000),
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
            // Quick, short answers: little thinking needed. Effort and server-side
            // fallbacks exist only on the newer models.
            if supportsEffort(model) { body["output_config"] = ["effort": "low"] }
            if supportsFallbacks(model) {
                headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
                body["fallbacks"] = "default"
            }
            return AIRequest(url: url, headers: headers, body: body)

        case .openAI:
            guard let url = URL(string: base + "/chat/completions"), url.scheme?.hasPrefix("http") == true else { throw Problem.badURL }
            var headers = ["Content-Type": "application/json"]
            if let key { headers["Authorization"] = "Bearer \(key)" }
            if provider == .openRouter {
                headers["HTTP-Referer"] = "https://github.com/dhruvv620/notchflow"
                headers["X-Title"] = "NotchFlow"
            }
            var body: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ]
            if provider == .openAI {
                // Newer OpenAI models take only max_completion_tokens and the default temperature.
                body["max_completion_tokens"] = maxTokens
            } else {
                body["max_tokens"] = maxTokens
                body["temperature"] = 0.4
            }
            return AIRequest(url: url, headers: headers, body: body)
        }
    }

    static func supportsEffort(_ model: String) -> Bool {
        ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable-5", "claude-opus-4-8", "claude-opus-4-7"]
            .contains { model.hasPrefix($0) }
    }

    static func supportsFallbacks(_ model: String) -> Bool {
        ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]
            .contains { model == $0 }
    }

    /// The answer's text, without reasoning in `<think>` tags.
    static func text(fromResponse data: Data, format: AIProvider.Format) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw: String?
        switch format {
        case .anthropic:
            let blocks = object["content"] as? [[String: Any]] ?? []
            let texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            raw = texts.isEmpty ? nil : texts.joined(separator: "\n")
        case .openAI:
            let choices = object["choices"] as? [[String: Any]]
            raw = (choices?.first?["message"] as? [String: Any])?["content"] as? String
        }
        guard let raw else { return nil }
        let cleaned = raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// An error the service explained, from any of the usual shapes.
    static func errorMessage(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = object["error"] as? String { return message }
        if let base = object["base_resp"] as? [String: Any], let code = base["status_code"] as? Int, code != 0 {
            return base["status_msg"] as? String ?? "error \(code)"
        }
        if object["stop_reason"] as? String == "refusal" { return "The model declined to answer." }
        return ""
    }

    /// A JSON array or object inside a model's answer (which may wrap it in
    /// code fences or a sentence).
    static func jsonPayload(in text: String) -> Any? {
        let cleaned = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        for (open, close) in [("[", "]"), ("{", "}")] {
            guard let start = cleaned.firstIndex(of: Character(open)), let end = cleaned.lastIndex(of: Character(close)), start < end,
                  let data = String(cleaned[start...end]).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else { continue }
            return value
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
