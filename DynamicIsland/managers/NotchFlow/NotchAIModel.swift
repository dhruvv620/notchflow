// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

struct NotchChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: String
    let text: String
}

@MainActor
final class NotchAIModel: ObservableObject {
    static let shared = NotchAIModel()
    @Published private(set) var messages: [NotchChatMessage] = []
    @Published private(set) var running = false
    @Published var error: String?
    @Published var provider: NotchAIProvider = .codex
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    func executableURL() -> URL? {
        let override = UserDefaults.standard.string(forKey: "notchflowCLI-\(provider.executable)") ?? ""
        if !override.isEmpty { return FileManager.default.isExecutableFile(atPath: override) ? URL(fileURLWithPath: override) : nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home.appendingPathComponent(".local/bin").path,
                     home.appendingPathComponent(".npm-global/bin").path, home.appendingPathComponent(".volta/bin").path,
                     home.appendingPathComponent(".bun/bin").path, home.appendingPathComponent(".claude/local").path,
                     "/Applications/Codex.app/Contents/Resources"]
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(provider.executable) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !text.isEmpty else { return }
        guard let executable = executableURL() else {
            error = "Install and sign in to \(provider.rawValue) in Terminal, or choose its executable with Setup."
            return
        }
        guard text.utf8.count <= 16_000 else { error = "Please keep each message under 16 KB."; return }
        error = nil
        let history = messages.suffix(12).map { "\($0.role): \($0.text.prefix(8_000))" }.joined(separator: "\n\n")
        let prompt = "You are a concise assistant in NotchFlow. Answer the user's question as text. Do not run commands, change files, or use external tools. Previous conversation follows as context.\n\n\(history)\n\nuser: \(text)"
        messages.append(.init(role: "user", text: text))
        running = true
        let id = UUID()
        requestID = id
        let selectedProvider = provider
        let runner = NotchCLIRunner()
        task = Task {
            do {
                let reply = try await withTaskCancellationHandler {
                    try await Task.detached {
                        try runner.execute(executable: executable, provider: selectedProvider, prompt: prompt)
                    }.value
                } onCancel: { runner.cancel() }
                guard requestID == id else { return }
                messages.append(.init(role: selectedProvider.rawValue, text: reply))
            } catch {
                guard requestID == id else { return }
                self.error = error.localizedDescription
            }
            guard requestID == id else { return }
            running = false
            task = nil
        }
    }

    func cancel() {
        requestID = nil
        task?.cancel()
        task = nil
        running = false
    }

    func newChat() { cancel(); messages = []; error = nil }
}

