// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Defaults
import Foundation
import SwiftUI

extension Defaults.Keys {
    /// New tasks for Claude Code and Codex open in a terminal window instead of running in the notch.
    static let agentRunInTerminal = Key<Bool>("agentRunInTerminal", default: false)
}

/// Agent conversations in the notch: recent Claude Code and Codex sessions
/// read from the files those tools keep, the selected session's chat
/// (refreshed while the agent writes), and runs started from the notch.
///
/// Runs use the agents' non-interactive modes (`claude -p --resume`,
/// `codex exec resume`) in a login shell, in the session's folder. Their
/// approvals arrive through the same hooks as terminal sessions.
@MainActor
final class AgentConversations: ObservableObject {
    static let shared = AgentConversations()

    @Published private(set) var recent: [AgentSessionSummary] = []
    @Published private(set) var selected: AgentSessionSummary?
    @Published private(set) var items: [AgentChatItem] = []
    /// Messages sent from the notch that the transcript doesn't show yet.
    @Published private(set) var pendingMessages: [String] = []
    /// Session ids with a run started from the notch still going.
    @Published private(set) var running: Set<String> = []
    /// A new session started from the notch, until it announces its id.
    @Published private(set) var startingNewSession = false
    @Published private(set) var lastError: String?

    private var processes: [String: Process] = [:]
    private var refreshTimer: AnyCancellable?
    private var selectedModified: Date?
    private var listRefreshedAt = Date.distantPast

    private init() {}

    nonisolated static var claudeRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects") }
    nonisolated static var codexRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions") }

    // MARK: Recent sessions

    func refreshList(force: Bool = false) {
        guard force || Date().timeIntervalSince(listRefreshedAt) > 5 else { return }
        listRefreshedAt = Date()
        Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run { AgentConversations.shared.recent = found }
        }
    }

    /// The 40 most recently active sessions of the last two weeks. Only the
    /// start of each file is read for the title.
    nonisolated static func scan() -> [AgentSessionSummary] {
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        func files(under root: URL, matching: (URL) -> Bool) -> [(URL, Date)] {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [.skipsHiddenFiles]) else { return [] }
            var result: [(URL, Date)] = []
            for case let url as URL in enumerator where matching(url) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if modified > cutoff { result.append((url, modified)) }
            }
            return result
        }
        let claude = files(under: claudeRoot) { $0.pathExtension == "jsonl" && !$0.path.contains("/subagents/") }
        let codex = files(under: codexRoot) { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        let newest = (claude.map { ($0.0, $0.1, AgentSessionSummary.Agent.claude) } + codex.map { ($0.0, $0.1, AgentSessionSummary.Agent.codex) })
            .sorted { $0.1 > $1.1 }
            .prefix(40)
        return newest.compactMap { url, modified, agent in
            guard let head = readHead(of: url, bytes: 96 * 1024) else { return nil }
            switch agent {
            case .claude: return AgentTranscriptPolicy.claudeSummary(from: head, fileURL: url, modified: modified)
            case .codex: return AgentTranscriptPolicy.codexSummary(from: head, fileURL: url, modified: modified)
            }
        }
    }

    nonisolated private static func readHead(of url: URL, bytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: bytes)
    }

    /// The end of a transcript: long sessions show their last few megabytes.
    nonisolated private static func readTail(of url: URL, bytes: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        return try? handle.readToEnd()
    }

    // MARK: The open conversation

    func select(_ summary: AgentSessionSummary?) {
        selected = summary
        items = []
        pendingMessages = []
        selectedModified = nil
        lastError = nil
        refreshTimer = nil
        guard summary != nil else { return }
        reloadSelected()
        // The agent appends to its file as it works; follow it while the chat is open.
        refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.reloadSelectedIfChanged() }
    }

    /// Opens the conversation of a live session, by its id.
    func select(sessionID: String) {
        if let summary = recent.first(where: { $0.id == sessionID }) {
            select(summary)
            return
        }
        Task.detached(priority: .userInitiated) {
            let found = Self.scan()
            await MainActor.run {
                let conversations = AgentConversations.shared
                conversations.recent = found
                conversations.select(found.first { $0.id == sessionID })
            }
        }
    }

    func stopFollowing() {
        refreshTimer = nil
    }

    private func reloadSelectedIfChanged() {
        guard let url = selected?.fileURL else { return }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        guard modified != selectedModified else { return }
        reloadSelected()
    }

    private func reloadSelected() {
        guard let summary = selected else { return }
        let url = summary.fileURL
        selectedModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        Task.detached(priority: .userInitiated) {
            guard let data = Self.readTail(of: url, bytes: 4 * 1024 * 1024) else { return }
            let parsed = summary.agent == .claude
                ? AgentTranscriptPolicy.claudeItems(from: data)
                : AgentTranscriptPolicy.codexItems(from: data)
            await MainActor.run {
                let conversations = AgentConversations.shared
                guard conversations.selected?.id == summary.id else { return }
                conversations.items = Array(parsed.suffix(300))
                // A sent message is no longer pending once the transcript has it.
                let userTexts = Set(parsed.filter { $0.role == .user }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
                conversations.pendingMessages.removeAll { userTexts.contains($0) }
            }
        }
    }

    // MARK: Sending

    var canSend: Bool {
        guard let selected, !running.contains(selected.id) else { return false }
        // Busy in its own terminal: wait for that turn, then reply here.
        if let live = AgentHub.shared.sessions.first(where: { $0.id == selected.id }), live.isWorking || live.isWaiting {
            return AgentHub.shared.canReply(to: live)
        }
        return true
    }

    /// Sends a message to the open conversation. A Claude Code session that
    /// is waiting in its terminal gets it there (it wakes and continues);
    /// otherwise the agent runs here in the background.
    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = selected, !message.isEmpty, canSend else { return }
        lastError = nil
        pendingMessages.append(message)
        let hub = AgentHub.shared
        if let live = hub.sessions.first(where: { $0.id == summary.id }), hub.canReply(to: live) {
            hub.reply(to: live, text: message)
            return
        }
        run(command: AgentTranscriptPolicy.continueCommand(agent: summary.agent, sessionID: summary.id, message: message),
            in: summary.cwd, sessionID: summary.id)
    }

    /// Starts a new session in the background and opens it when it has an id.
    func start(agent: AgentSessionSummary.Agent, prompt: String, directory: String) {
        let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        lastError = nil
        startingNewSession = true
        if !directory.isEmpty { AgentHub.shared.rememberProject(directory) }
        run(command: AgentTranscriptPolicy.startCommand(agent: agent, message: message), in: directory, sessionID: nil)
    }

    func stop(_ sessionID: String) {
        processes[sessionID]?.terminate()
    }

    private func run(command: String, in directory: String, sessionID: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = AgentTranscriptPolicy.shellInvocation(command)
        let folder = directory.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : directory
        if FileManager.default.fileExists(atPath: folder) { process.currentDirectoryURL = URL(fileURLWithPath: folder) }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        let key = sessionID ?? "new-\(UUID().uuidString)"
        let buffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in buffer.append(data) {
                let id = AgentTranscriptPolicy.sessionID(fromStreamLine: line)
                let failure = AgentTranscriptPolicy.failure(fromStreamLine: line)
                let notFound = line.contains("command not found")
                guard id != nil || failure != nil || notFound else { continue }
                Task { @MainActor in
                    let conversations = AgentConversations.shared
                    if let id, sessionID == nil { conversations.adoptNewSession(id: id, key: key) }
                    if let failure { conversations.lastError = failure }
                    if notFound { conversations.lastError = "The agent's command was not found. Install it, or check that it runs in Terminal." }
                }
            }
        }
        process.terminationHandler = { finished in
            output.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            Task { @MainActor in
                let conversations = AgentConversations.shared
                conversations.finishRun(key: key, status: status)
            }
        }
        do {
            try process.run()
            processes[key] = process
            running.insert(key)
        } catch {
            lastError = "Could not start the agent: \(error.localizedDescription)"
            startingNewSession = false
            pendingMessages.removeAll()
        }
    }

    private func adoptNewSession(id: String, key: String) {
        guard let process = processes.removeValue(forKey: key) else { return }
        processes[id] = process
        running.remove(key)
        running.insert(id)
        startingNewSession = false
        // Its transcript appears once the agent writes it; select it then.
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let found = await Task.detached(priority: .userInitiated) { Self.scan() }.value
                recent = found
                if let summary = found.first(where: { $0.id == id }) {
                    select(summary)
                    return
                }
            }
        }
    }

    private func finishRun(key: String, status: Int32) {
        processes.removeValue(forKey: key)
        running.remove(key)
        if key.hasPrefix("new-") {
            startingNewSession = false
            if status != 0, lastError == nil { lastError = "The agent stopped before it started (exit \(status))." }
        } else if status != 0, status != 15, lastError == nil {
            lastError = "The agent stopped with exit code \(status)."
        }
        pendingMessages.removeAll()
        reloadSelected()
        refreshList(force: true)
    }

    func isRunning(_ sessionID: String) -> Bool { running.contains(sessionID) }
}

/// Splits a byte stream into complete lines across reads.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }
}
