// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation

extension Defaults.Keys {
    /// The AI service smart replies and promise detection use.
    static let aiProvider = Key<String>("aiProvider", default: AIProvider.minimax.rawValue)
    /// Per-provider address and model, when changed from the defaults.
    static let aiBaseURLs = Key<[String: String]>("aiBaseURLs", default: [:])
    static let aiModels = Key<[String: String]>("aiModels", default: [:])
    /// MiniMax's address and model from before there was a choice of provider.
    static let minimaxBaseURL = Key<String>("minimaxBaseURL", default: "https://api.minimax.io/v1")
    static let minimaxModel = Key<String>("minimaxModel", default: "MiniMax-M2")
}

/// Sends one prompt to the chosen AI provider with the user's own key (kept
/// in the Keychain, one per provider) and returns the answer's text.
enum AIClient {
    enum ClientError: LocalizedError {
        case notSetUp(String), badURL(String), noModel(String), http(String, Int, String), empty(String)
        var errorDescription: String? {
            switch self {
            case .notSetUp(let name): return "Add your \(name) API key in Settings › Smart Tools › AI provider."
            case .badURL(let name): return "The \(name) address in Settings › Smart Tools is not a valid URL."
            case .noModel(let name): return "Choose a \(name) model in Settings › Smart Tools."
            case .http(let name, let code, let message): return message.isEmpty ? "\(name) answered \(code)." : "\(name): \(message)"
            case .empty(let name): return "\(name) sent an empty answer."
            }
        }
    }

    static var provider: AIProvider { AIProvider(rawValue: Defaults[.aiProvider]) ?? .minimax }

    static func baseURL(for provider: AIProvider) -> String {
        if let saved = Defaults[.aiBaseURLs][provider.rawValue] { return saved }
        return provider == .minimax ? Defaults[.minimaxBaseURL] : provider.defaultBaseURL
    }

    static func model(for provider: AIProvider) -> String {
        if let saved = Defaults[.aiModels][provider.rawValue] { return saved }
        return provider == .minimax ? Defaults[.minimaxModel] : provider.defaultModel
    }

    static func setBaseURL(_ value: String, for provider: AIProvider) { Defaults[.aiBaseURLs][provider.rawValue] = value }
    static func setModel(_ value: String, for provider: AIProvider) { Defaults[.aiModels][provider.rawValue] = value }

    private static func account(for provider: AIProvider) -> String {
        provider == .minimax ? SecretStore.Secret.minimaxAPIKey.rawValue : "ai-key-\(provider.rawValue)"
    }

    static func key(for provider: AIProvider) -> String? { SecretStore.read(account: account(for: provider)) }
    static func hasKey(_ provider: AIProvider) -> Bool { key(for: provider) != nil }
    @discardableResult
    static func setKey(_ value: String, for provider: AIProvider) -> Bool { SecretStore.write(value, account: account(for: provider)) }

    /// Whether the provider can be asked: a key when it needs one, an address and a model.
    static func isReady(_ provider: AIProvider = provider) -> Bool {
        (!provider.needsKey || hasKey(provider))
            && !baseURL(for: provider).trimmingCharacters(in: .whitespaces).isEmpty
            && !model(for: provider).trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func complete(system: String, user: String, maxTokens: Int, provider: AIProvider = provider) async throws -> String {
        let name = provider == .custom ? "The custom AI" : provider.title
        let request: AIRequest
        do {
            request = try AIProviderPolicy.request(provider: provider, baseURL: baseURL(for: provider), model: model(for: provider),
                                                   key: key(for: provider), system: system, user: user, maxTokens: maxTokens)
        } catch AIProviderPolicy.Problem.noKey {
            throw ClientError.notSetUp(provider.title)
        } catch AIProviderPolicy.Problem.noModel {
            throw ClientError.noModel(provider.title)
        } catch {
            throw ClientError.badURL(provider.title)
        }
        var urlRequest = URLRequest(url: request.url, timeoutInterval: provider.runsOnThisMac ? 90 : 45)
        urlRequest.httpMethod = "POST"
        for (field, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request.body)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ClientError.http(name, status, AIProviderPolicy.errorMessage(in: data)) }
        guard let text = AIProviderPolicy.text(fromResponse: data, format: provider.format) else {
            // Some services report errors with HTTP 200.
            let message = AIProviderPolicy.errorMessage(in: data)
            throw message.isEmpty ? ClientError.empty(name) : ClientError.http(name, status, message)
        }
        return text
    }
}
