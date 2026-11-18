// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// The AI Agents tab, closed-notch status and the local bridge the `notchflow` command uses.
    static let enableAgentsFeature = Key<Bool>("enableAgentsFeature", default: true)
    /// How long an approval waits in the notch before the agent asks in its own window.
    static let agentApprovalWaitSeconds = Key<Int>("agentApprovalWaitSeconds", default: 120)
    /// When the agent's own window is in front, let it ask there instead of the notch.
    static let agentAskInWindowWhenInFront = Key<Bool>("agentAskInWindowWhenInFront", default: true)
    /// Show "working" status under the closed notch (needs-you and done always show).
    static let agentShowWorkingInClosedNotch = Key<Bool>("agentShowWorkingInClosedNotch", default: true)
}

enum AgentKind: String, Sendable {
    case claudeCode = "claude-code"
    case script

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .script: return "Script"
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .script: return "terminal"
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    enum State: Equatable {
        case ready
        case working(String)
        case waiting(String)
        case done(String)
    }

    let id: String
    let agent: AgentKind
    var project: String
    var cwd: String
    var appBundleID: String?
    var state: State
    var lastPrompt: String?
    var turnStartedAt: Date?
    var updatedAt: Date

    var isWorking: Bool { if case .working = state { return true }; return false }
    var isWaiting: Bool { if case .waiting = state { return true }; return false }
}

/// Something an agent is waiting on you for.
struct AgentRequest: Identifiable {
    enum Kind {
        case permission(title: String, detail: String, risk: AgentRisk, canAlwaysAllow: Bool)
        case question([AgentQuestion])
        case ask(question: String, options: [String])
    }

    let id = UUID()
    let sessionID: String?
    let agent: AgentKind
    let project: String
    let appBundleID: String?
    let kind: Kind
    let createdAt = Date()
}

enum AgentDecision {
    case allow
    case allowAlways
    case deny(String)
    /// No answer from the notch: the agent asks in its own window.
    case inWindow
    case answers([String: String])
    case choice(String)
}

/// Sessions and requests from AI agents, received over `AgentBridgeServer`.
@MainActor
final class AgentHub: ObservableObject {
    static let shared = AgentHub()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var requests: [AgentRequest] = []
    /// A session that just finished, flashed under the closed notch.
    @Published private(set) var announcement: AgentSession?
    @Published private(set) var bridgeError: String?
    @Published private(set) var isBridgeRunning = false

    /// Readable outside the main actor, for the tab list.
    nonisolated(unsafe) static var hasPendingRequest = false

    private var server: AgentBridgeServer?
    private var waiters: [UUID: CheckedContinuation<AgentDecision, Never>] = [:]
    private var hookInputs: [UUID: AgentHookEvent] = [:]
    private var announcementWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private var started = false

    static var bridgeFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchFlow/agent-bridge.env")
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        Defaults.publisher(.enableAgentsFeature)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                if change.newValue { self?.startBridge() } else { self?.stopBridge() }
            }
            .store(in: &subscriptions)
        // Sessions that went quiet (terminal closed without SessionEnd) are dropped.
        Timer.publish(every: 300, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.pruneStaleSessions() }
            .store(in: &subscriptions)
    }

    // MARK: Bridge

    private func startBridge() {
        guard server == nil else { return }
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        let server = AgentBridgeServer(token: token) { request in
            await AgentHub.shared.handle(request)
        }
        self.server = server
        Task { @MainActor in
            do {
                let port = try await server.start()
                try Self.writeBridgeFile(port: port, token: token)
                isBridgeRunning = true
                bridgeError = nil
            } catch {
                bridgeError = error.localizedDescription
                isBridgeRunning = false
                self.server = nil
            }
        }
    }

    private func stopBridge() {
        server?.stop()
        server = nil
        isBridgeRunning = false
        try? FileManager.default.removeItem(at: Self.bridgeFileURL)
        for id in Array(waiters.keys) { finish(id, with: .inWindow) }
    }

    private static func writeBridgeFile(port: UInt16, token: String) throws {
        let url = bridgeFileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let contents = "NOTCHFLOW_PORT=\(port)\nNOTCHFLOW_TOKEN=\(token)\n"
        FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8), attributes: [.posixPermissions: 0o600])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Requests from the notchflow command

    func handle(_ request: AgentBridgeServer.Request) async -> AgentBridgeServer.Response {
        let app = request.headers["x-notchflow-app"].flatMap { $0.isEmpty ? nil : $0 }
        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            return .text("NotchFlow is running and listening for agents.\n")
        case ("POST", "/v1/hook/claude-code"), ("POST", "/v1/hook/claude-code/status"):
            guard let event = AgentHookEvent.parse(request.body) else { return .empty }
            return await handleClaudeCode(event, app: app, waits: !request.path.hasSuffix("/status"))
        case ("POST", "/v1/ask"):
            let fields = AgentBridgeServer.formFields(request.body)
            let options = (fields["options"] ?? "Yes,No").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let ask = AgentRequest(sessionID: nil, agent: .script, project: fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? "Script",
                                   appBundleID: app, kind: .ask(question: fields["question"] ?? "", options: options.isEmpty ? ["OK"] : options))
            if case .choice(let choice) = await wait(for: ask) { return .text(choice) }
            return AgentBridgeServer.Response(status: 204)
        case ("POST", "/v1/notify"):
            let fields = AgentBridgeServer.formFields(request.body)
            let title = fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? "Script"
            announce(AgentSession(id: "notify-\(UUID().uuidString)", agent: .script, project: title, cwd: "",
                                  appBundleID: app, state: .done(fields["message"] ?? ""), updatedAt: Date()))
            return .empty
        default:
            return .text("Unknown request\n", status: 404)
        }
    }

    /// `waits` is false for background (status) hooks: they update the status
    /// and never open an approval or a question.
    private func handleClaudeCode(_ event: AgentHookEvent, app: String?, waits: Bool) async -> AgentBridgeServer.Response {
        var session = sessions.first { $0.id == event.sessionID }
            ?? AgentSession(id: event.sessionID, agent: .claudeCode, project: event.projectName, cwd: event.cwd,
                            appBundleID: app, state: .ready, updatedAt: Date())
        if !event.cwd.isEmpty { session.cwd = event.cwd; session.project = event.projectName }
        if let app { session.appBundleID = app }
        session.updatedAt = Date()

        switch event.name {
        case "SessionStart":
            session.state = .ready
        case "UserPromptSubmit":
            finishPending(for: session.id)
            session.lastPrompt = event.message
            session.turnStartedAt = Date()
            session.state = .working("Thinking")
        case "PreToolUse":
            let tool = event.toolName ?? ""
            if tool == "AskUserQuestion" {
                let questions = AgentHookPolicy.questions(from: event.toolInput)
                guard !questions.isEmpty else { break }
                // The status copy of this event arrives too; only the waiting one asks.
                guard waits, !skipNotch(for: session) else {
                    session.state = .waiting("Has a question for you")
                    break
                }
                session.state = .waiting("Has a question for you")
                upsert(session)
                let request = AgentRequest(sessionID: session.id, agent: .claudeCode, project: session.project,
                                           appBundleID: session.appBundleID, kind: .question(questions))
                let decision = await wait(for: request)
                updateState(of: session.id, to: .working("Continuing"))
                if case .answers(let answers) = decision {
                    return .json(AgentHookPolicy.questionAnswers(input: event.toolInput, answers: answers))
                }
                return .empty
            }
            if !session.isWaiting { session.state = .working(AgentHookPolicy.activity(tool: tool, input: event.toolInput)) }
        case "PostToolUse":
            // The tool finished; keep showing it until the next one starts.
            if session.state == .ready { session.state = .working("Thinking") }
        case "PermissionRequest":
            let tool = event.toolName ?? ""
            let (title, detail) = AgentHookPolicy.describe(tool: tool, input: event.toolInput)
            let risk = AgentHookPolicy.risk(tool: tool, input: event.toolInput)
            guard waits, !skipNotch(for: session) else {
                session.state = .waiting("Asking in its window: \(title)")
                upsert(session)
                return .empty
            }
            session.state = .waiting(title)
            upsert(session)
            let request = AgentRequest(sessionID: session.id, agent: .claudeCode, project: session.project,
                                       appBundleID: session.appBundleID,
                                       kind: .permission(title: title, detail: detail, risk: risk,
                                                         canAlwaysAllow: risk != .danger && !event.permissionSuggestions.isEmpty))
            hookInputs[request.id] = event
            let decision = await wait(for: request)
            hookInputs[request.id] = nil
            switch decision {
            case .allow:
                updateState(of: session.id, to: .working("Continuing"))
                return .json(AgentHookPolicy.permissionAllow())
            case .allowAlways:
                updateState(of: session.id, to: .working("Continuing"))
                return .json(AgentHookPolicy.permissionAllow(alwaysRules: event.permissionSuggestions))
            case .deny(let message):
                updateState(of: session.id, to: .working("Changing course"))
                return .json(AgentHookPolicy.permissionDeny(message: message))
            default:
                updateState(of: session.id, to: .waiting("Asking in its window: \(title)"))
                return .empty
            }
        case "Notification":
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog", "agent_needs_input":
                session.state = .waiting(event.message ?? "Needs you")
            case "idle_prompt":
                if case .done = session.state {} else { session.state = .ready }
            default:
                break
            }
        case "Stop":
            finishPending(for: session.id)
            let summary = AgentHookPolicy.summary(of: event.message)
            session.state = .done(summary.isEmpty ? "Finished" : summary)
            upsert(session)
            announce(session)
            return .empty
        case "SessionEnd":
            finishPending(for: session.id)
            sessions.removeAll { $0.id == session.id }
            return .empty
        default:
            break
        }
        upsert(session)
        return .empty
    }

    /// Let the agent ask in its own window when that window is in front of you.
    private func skipNotch(for session: AgentSession) -> Bool {
        guard Defaults[.enableAgentsFeature] else { return true }
        guard Defaults[.agentAskInWindowWhenInFront], let app = session.appBundleID else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app
    }

    // MARK: Waiting for an answer

    private func wait(for request: AgentRequest) async -> AgentDecision {
        let seconds = max(15, min(600, Defaults[.agentApprovalWaitSeconds]))
        return await withCheckedContinuation { continuation in
            waiters[request.id] = continuation
            withAnimation(.smooth(duration: 0.25)) { requests.append(request) }
            Self.hasPendingRequest = true
            NSSound(named: "Tink")?.play()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                self?.finish(request.id, with: .inWindow)
            }
        }
    }

    /// Your answer from the notch.
    func resolve(_ request: AgentRequest, with decision: AgentDecision) {
        finish(request.id, with: decision)
    }

    private func finish(_ id: UUID, with decision: AgentDecision) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        withAnimation(.smooth(duration: 0.25)) { requests.removeAll { $0.id == id } }
        Self.hasPendingRequest = !requests.isEmpty
        continuation.resume(returning: decision)
    }

    /// A new prompt, a stop or the end of the session means the terminal moved on.
    private func finishPending(for sessionID: String) {
        for request in requests where request.sessionID == sessionID { finish(request.id, with: .inWindow) }
    }

    // MARK: Sessions

    private func upsert(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if sessions[index] != session { sessions[index] = session }
        } else {
            withAnimation(.smooth(duration: 0.25)) { sessions.insert(session, at: 0) }
        }
    }

    private func updateState(of sessionID: String, to state: AgentSession.State) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].state = state
        sessions[index].updatedAt = Date()
    }

    private func announce(_ session: AgentSession) {
        withAnimation(.smooth(duration: 0.25)) { announcement = session }
        announcementWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth(duration: 0.25)) { self?.announcement = nil }
        }
        announcementWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func dismissAnnouncement() {
        announcementWork?.cancel()
        withAnimation(.smooth(duration: 0.25)) { announcement = nil }
    }

    func dismiss(_ session: AgentSession) {
        withAnimation(.smooth(duration: 0.25)) { sessions.removeAll { $0.id == session.id } }
    }

    private func pruneStaleSessions() {
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        let pendingSessions = Set(requests.compactMap(\.sessionID))
        sessions.removeAll { $0.updatedAt < cutoff && !pendingSessions.contains($0.id) }
    }

    /// Brings the agent's window (terminal or editor) to the front.
    func openWindow(bundleID: String?) {
        guard let bundleID else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Test

    /// A sample approval, for Settings > AI Agents.
    func sendTestRequest() {
        let request = AgentRequest(sessionID: nil, agent: .claudeCode, project: "notchflow (test)", appBundleID: nil,
                                   kind: .permission(title: "Run a command", detail: "npm test -- --watch=false",
                                                     risk: .normal, canAlwaysAllow: false))
        Task { @MainActor in _ = await wait(for: request) }
    }

    var waitingCount: Int { requests.count }
    var workingSessions: [AgentSession] { sessions.filter(\.isWorking) }
}
