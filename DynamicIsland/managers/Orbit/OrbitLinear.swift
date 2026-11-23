// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation
import os

extension Defaults.Keys {
    /// Two-way Linear: your assigned issues in Loops, and issues made from the notch.
    static let orbitLinear = Key<Bool>("orbitLinear", default: false)
    /// The team new issues go to (its id). Empty means the first team.
    static let orbitLinearTeam = Key<String>("orbitLinearTeam", default: "")
    /// Comment on a Linear issue when an AI agent finishes work that names it.
    static let orbitLinearAgentComments = Key<Bool>("orbitLinearAgentComments", default: false)
}

/// Talks to Linear's GraphQL API with a personal API key from the Keychain.
/// Runs only while Orbit and its Linear switch are on: one fetch every five
/// minutes, nothing at all otherwise.
@MainActor
final class OrbitLinear: ObservableObject {
    static let shared = OrbitLinear()

    @Published private(set) var issues: [LinearIssue] = []
    @Published private(set) var teams: [LinearTeam] = []
    @Published private(set) var accountName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private let log = os.Logger(subsystem: "com.dhruvv620.NotchFlow", category: "OrbitLinear")
    private var timer: Timer?
    @Published private(set) var isActive = false
    private static let interval: TimeInterval = 300

    private init() {}

    var hasKey: Bool { SecretStore.has(.linear) }

    func saveKey(_ key: String) {
        SecretStore.write(key, for: .linear)
        accountName = nil
        lastError = nil
        if isActive { Task { await refresh() } }
    }

    /// Called by Orbit when its switches change.
    func setActive(_ active: Bool) {
        let shouldRun = active && Defaults[.orbitLinear]
        guard shouldRun != isActive else { return }
        isActive = shouldRun
        if shouldRun {
            timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
                Task { @MainActor in await OrbitLinear.shared.refresh() }
            }
            timer?.tolerance = 60
            Task { await refresh() }
        } else {
            timer?.invalidate()
            timer = nil
            issues = []
            teams = []
            accountName = nil
            lastError = nil
        }
    }

    // MARK: Requests

    private enum LinearError: LocalizedError {
        case noKey, server(String), badReply
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add a Linear API key in Settings › Orbit."
            case .server(let message): return message
            case .badReply: return "Linear sent an unexpected reply."
            }
        }
    }

    private func send(_ body: Data?) async throws -> Data {
        guard let key = SecretStore.read(.linear) else { throw LinearError.noKey }
        guard let body else { throw LinearError.badReply }
        var request = URLRequest(url: OrbitLoopsPolicy.endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Personal API keys go as they are; OAuth tokens need "Bearer".
        request.setValue(key.hasPrefix("lin_oauth") ? "Bearer \(key)" : key, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let message = OrbitLoopsPolicy.error(in: data) { throw LinearError.server(message) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinearError.server(http.statusCode == 401 ? "Linear didn't accept the API key." : "Linear answered \(http.statusCode).")
        }
        return data
    }

    /// Fetches your open assigned issues (and the teams, once).
    func refresh() async {
        guard isActive, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let data = try await send(OrbitLoopsPolicy.body(OrbitLoopsPolicy.viewerQuery))
            guard isActive, let viewer = OrbitLoopsPolicy.viewer(from: data) else { throw LinearError.badReply }
            let previous = issues
            issues = viewer.issues
            accountName = viewer.name
            lastError = nil
            if !previous.isEmpty {
                for move in OrbitLoopsPolicy.moves(from: previous, to: viewer.issues) {
                    Orbit.shared.linearIssueMoved(move.issue, from: move.from)
                }
            }
            if teams.isEmpty {
                let teamData = try await send(OrbitLoopsPolicy.body(OrbitLoopsPolicy.teamsQuery))
                if isActive { teams = OrbitLoopsPolicy.teams(from: teamData) }
            }
        } catch {
            guard isActive else { return }
            lastError = error.localizedDescription
            log.error("Linear refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var targetTeam: LinearTeam? {
        let chosen = Defaults[.orbitLinearTeam]
        return teams.first { $0.id == chosen } ?? teams.first
    }

    /// Makes an issue in the chosen team. Returns its identifier.
    @discardableResult
    func createIssue(title: String, description: String, project: String?) async -> String? {
        guard isActive else { return nil }
        if teams.isEmpty { await refresh() }
        guard let team = targetTeam else {
            lastError = lastError ?? "No Linear team found."
            return nil
        }
        do {
            let data = try await send(OrbitLoopsPolicy.createIssueBody(teamID: team.id, title: title, description: description))
            guard let created = OrbitLoopsPolicy.createdIssue(from: data) else { throw LinearError.badReply }
            Orbit.shared.linearIssueCreated(identifier: created.identifier, title: title, url: created.url, project: project)
            await refresh()
            return created.identifier
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Moves an issue to its team's first "started" or "completed" state.
    func move(issueID: String, toType type: String) async {
        guard isActive, let issue = issues.first(where: { $0.id == issueID }) else { return }
        if teams.isEmpty { await refresh() }
        guard let team = teams.first(where: { $0.id == issue.teamID }),
              let state = OrbitLoopsPolicy.state(ofType: type, in: team) else {
            lastError = "Couldn't find a \(type) state in \(issue.teamName)."
            return
        }
        do {
            let data = try await send(OrbitLoopsPolicy.moveIssueBody(issueID: issue.id, stateID: state.id))
            guard OrbitLoopsPolicy.succeeded(data, operation: "issueUpdate") else { throw LinearError.badReply }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Comments on one of your issues, by identifier ("ENG-12").
    func comment(onIdentifier identifier: String, text: String) async {
        guard isActive, let issue = issues.first(where: { $0.identifier == identifier }) else { return }
        do {
            let data = try await send(OrbitLoopsPolicy.commentBody(issueID: issue.id, text: text))
            guard OrbitLoopsPolicy.succeeded(data, operation: "commentCreate") else { throw LinearError.badReply }
        } catch {
            lastError = error.localizedDescription
        }
    }

    var teamKeys: Set<String> { Set(issues.map(\.teamKey) + teams.map(\.key)) }
}
