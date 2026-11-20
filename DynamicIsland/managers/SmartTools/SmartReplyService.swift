// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation

extension Defaults.Keys {
    /// Suggest three short replies with the user's own AI key.
    static let enableSmartReplies = Key<Bool>("enableSmartReplies", default: false)
}

/// Asks the chosen AI provider for three short replies. Only runs when the
/// user taps the sparkles button, so a message never leaves the Mac unless
/// they ask.
@MainActor
final class SmartReplyService: ObservableObject {
    static let shared = SmartReplyService()

    @Published private(set) var suggestions: [String: [String]] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private init() {}

    static var isAvailable: Bool { Defaults[.enableSmartReplies] && AIClient.isReady() }

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

    static func fetch(sender: String, message: String, context: [String], provider: AIProvider = AIClient.provider) async throws -> [String] {
        let prompt = SmartReplyPolicy.prompt(sender: sender, message: message, context: context)
        let answer = try await AIClient.complete(system: prompt.system, user: prompt.user, maxTokens: 600, provider: provider)
        let replies = SmartReplyPolicy.suggestions(fromText: answer)
        if replies.isEmpty { throw AIClient.ClientError.empty(provider.title) }
        return replies
    }
}
