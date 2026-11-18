// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation

extension Defaults.Keys {
    /// Suggest three short replies with the user's own MiniMax key.
    static let enableSmartReplies = Key<Bool>("enableSmartReplies", default: false)
    static let minimaxBaseURL = Key<String>("minimaxBaseURL", default: "https://api.minimax.io/v1")
    static let minimaxModel = Key<String>("minimaxModel", default: "MiniMax-M2")
}

/// Asks MiniMax (its OpenAI-compatible chat completions API) for three short
/// replies. Only runs when the user taps the sparkles button, so a message
/// never leaves the Mac unless they ask.
@MainActor
final class SmartReplyService: ObservableObject {
    static let shared = SmartReplyService()

    enum ReplyError: LocalizedError {
        case noKey, badURL, http(Int, String), empty
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your MiniMax API key in Settings › Smart Tools."
            case .badURL: return "The MiniMax address in Settings is not a valid URL."
            case .http(let code, let message): return message.isEmpty ? "MiniMax answered \(code)." : "MiniMax: \(message)"
            case .empty: return "MiniMax sent no suggestions."
            }
        }
    }

    @Published private(set) var suggestions: [String: [String]] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private init() {}

    static var isAvailable: Bool { Defaults[.enableSmartReplies] && SecretStore.has(.minimaxAPIKey) }

    func clear(_ id: String) {
        suggestions[id] = nil
        errors[id] = nil
    }

    func suggest(id: String, sender: String, message: String, context: [String]) {
        guard !loading.contains(id) else { return }
        loading.insert(id)
        errors[id] = nil
        Task { @MainActor in
            defer { loading.remove(id) }
            do {
                suggestions[id] = try await Self.fetch(sender: sender, message: message, context: context)
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }

    static func fetch(sender: String, message: String, context: [String]) async throws -> [String] {
        guard let key = SecretStore.read(.minimaxAPIKey) else { throw ReplyError.noKey }
        let base = Defaults[.minimaxBaseURL].trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions"), url.scheme?.hasPrefix("http") == true else { throw ReplyError.badURL }
        let model = Defaults[.minimaxModel].trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: SmartReplyPolicy.requestBody(
            model: model.isEmpty ? "MiniMax-M2" : model, sender: sender, message: message, context: context))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ReplyError.http(status, errorMessage(in: data)) }
        // MiniMax reports some errors with HTTP 200 and a base_resp code.
        let apiError = errorMessage(in: data)
        let replies = SmartReplyPolicy.suggestions(fromResponse: data)
        if replies.isEmpty { throw apiError.isEmpty ? ReplyError.empty : ReplyError.http(status, apiError) }
        return replies
    }

    private static func errorMessage(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let base = object["base_resp"] as? [String: Any], let code = base["status_code"] as? Int, code != 0 {
            return base["status_msg"] as? String ?? "error \(code)"
        }
        return ""
    }
}
