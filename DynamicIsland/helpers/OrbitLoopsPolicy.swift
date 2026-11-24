// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Orbit Loops: one inbox of everything still open (an agent waiting on you,
// promises, unanswered messages, failing builds, Linear issues), plus the
// Linear GraphQL calls that make it two-way. Pure, tested in
// tests/OrbitRegression.swift.

/// Something still open.
struct OrbitLoop: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case agent, promise, theirPromise, message, build, linear
        var symbol: String {
            switch self {
            case .agent: return "sparkles"
            case .promise: return "hand.raised"
            case .theirPromise: return "hourglass"
            case .message: return "message"
            case .build: return "xmark.octagon"
            case .linear: return "circle.dashed"
            }
        }
        /// Lower comes first.
        var rank: Int {
            switch self {
            case .agent: return 0
            case .build: return 1
            case .promise: return 2
            case .message: return 3
            case .linear: return 4
            case .theirPromise: return 5
            }
        }
    }
    /// Stable across refreshes: "agent:<session>", "promise:<uuid>", "msg:<person>", ...
    let id: String
    let kind: Kind
    let title: String
    var detail: String = ""
    let date: Date
    var due: Date?
    var project: String?
    var person: String?
    /// The person's name as shown, for pinning them.
    var personName: String?
    var url: String?
    /// The Linear issue (its GraphQL id), for loops that are issues.
    var issueID: String?
}

struct LinearIssue: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let url: String
    let stateName: String
    let stateType: String
    let teamID: String
    let teamKey: String
    let teamName: String
    let projectName: String?
    let priority: Int
    let updatedAt: Date?
}

struct LinearState: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let position: Double
}

struct LinearTeam: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let key: String
    let name: String
    let states: [LinearState]
}

enum OrbitLoopsPolicy {
    /// How long a dismissal is remembered.
    static let dismissalMemory: TimeInterval = 30 * 86_400

    // MARK: Loops

    /// A message waiting for a reply.
    struct Message: Sendable {
        let app: String
        let sender: String
        let text: String
        let date: Date
    }

    /// One "Reply to …" loop per person, with their latest message.
    static func messageLoops(_ messages: [Message]) -> [OrbitLoop] {
        var latest: [String: (Message, Int)] = [:]
        for message in messages {
            guard let name = OrbitPolicy.personName(fromTitle: message.sender) else { continue }
            let key = OrbitPolicy.key(name)
            if let existing = latest[key] {
                latest[key] = (message.date > existing.0.date ? message : existing.0, existing.1 + 1)
            } else {
                latest[key] = (message, 1)
            }
        }
        return latest.map { key, value in
            let (message, count) = value
            let name = OrbitPolicy.personName(fromTitle: message.sender) ?? message.sender
            let more = count > 1 ? " (\(count) messages)" : ""
            return OrbitLoop(id: "msg:\(key)", kind: .message, title: "Reply to \(name)\(more)",
                             detail: "\(message.app): \(OrbitPolicy.clip(message.text, to: 90))",
                             date: message.date, person: key, personName: name)
        }
    }

    /// What to show: without dismissed loops (unless something newer came in),
    /// without snoozed ones, most urgent first.
    static func visible(_ loops: [OrbitLoop], dismissed: [String: Date], snoozed: [String: Date], now: Date) -> [OrbitLoop] {
        loops
            .filter { loop in
                if let until = snoozed[loop.id], until > now { return false }
                if let at = dismissed[loop.id], loop.date <= at { return false }
                return true
            }
            .sorted { a, b in
                let aOverdue = (a.due.map { $0 < now } ?? false) ? 0 : 1
                let bOverdue = (b.due.map { $0 < now } ?? false) ? 0 : 1
                if (a.kind.rank, aOverdue) != (b.kind.rank, bOverdue) {
                    return (a.kind.rank, aOverdue) < (b.kind.rank, bOverdue)
                }
                return a.date > b.date
            }
    }

    /// Drops dismissals and snoozes that no longer matter.
    static func pruned(_ marks: [String: Date], now: Date, keepFor: TimeInterval) -> [String: Date] {
        marks.filter { now.timeIntervalSince($0.value) < keepFor }
    }

    // MARK: Linear

    static let endpoint = URL(string: "https://api.linear.app/graphql")!

    static func body(_ query: String, variables: [String: Any] = [:]) -> Data? {
        var object: [String: Any] = ["query": query]
        if !variables.isEmpty { object["variables"] = variables }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static let viewerQuery = """
    query { viewer { id name assignedIssues(first: 50, orderBy: updatedAt, filter: { state: { type: { nin: ["completed", "canceled"] } } }) { nodes { id identifier title url priority updatedAt state { name type } team { id key name } project { name } } } } }
    """

    static let teamsQuery = """
    query { teams(first: 50) { nodes { id key name states { nodes { id name type position } } } } }
    """

    static let createIssueMutation = """
    mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id identifier url title } } }
    """

    static let updateIssueMutation = """
    mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }
    """

    static let commentMutation = """
    mutation($input: CommentCreateInput!) { commentCreate(input: $input) { success } }
    """

    static func createIssueBody(teamID: String, title: String, description: String) -> Data? {
        var input: [String: Any] = ["teamId": teamID, "title": OrbitPolicy.clip(title, to: 200)]
        if !description.isEmpty { input["description"] = description }
        return body(createIssueMutation, variables: ["input": input])
    }

    static func moveIssueBody(issueID: String, stateID: String) -> Data? {
        body(updateIssueMutation, variables: ["id": issueID, "input": ["stateId": stateID]])
    }

    static func commentBody(issueID: String, text: String) -> Data? {
        body(commentMutation, variables: ["input": ["issueId": issueID, "body": text]])
    }

    /// The first error message in a GraphQL reply.
    static func error(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = object["errors"] as? [[String: Any]], let first = errors.first else { return nil }
        return first["message"] as? String ?? "Linear returned an error."
    }

    private static func dataObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any]
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return isoFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// The signed-in user's name and open assigned issues.
    static func viewer(from data: Data) -> (name: String, issues: [LinearIssue])? {
        guard let viewer = dataObject(data)?["viewer"] as? [String: Any] else { return nil }
        let name = viewer["name"] as? String ?? "Linear"
        let nodes = (viewer["assignedIssues"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let issues: [LinearIssue] = nodes.compactMap { node in
            guard let id = node["id"] as? String, let identifier = node["identifier"] as? String,
                  let title = node["title"] as? String else { return nil }
            let state = node["state"] as? [String: Any] ?? [:]
            let team = node["team"] as? [String: Any] ?? [:]
            let project = node["project"] as? [String: Any]
            return LinearIssue(id: id, identifier: identifier, title: title, url: node["url"] as? String ?? "",
                               stateName: state["name"] as? String ?? "", stateType: state["type"] as? String ?? "",
                               teamID: team["id"] as? String ?? "", teamKey: team["key"] as? String ?? "",
                               teamName: team["name"] as? String ?? "", projectName: project?["name"] as? String,
                               priority: (node["priority"] as? NSNumber)?.intValue ?? 0, updatedAt: date(node["updatedAt"] as? String))
        }
        return (name, issues)
    }

    static func teams(from data: Data) -> [LinearTeam] {
        guard let nodes = (dataObject(data)?["teams"] as? [String: Any])?["nodes"] as? [[String: Any]] else { return [] }
        return nodes.compactMap { node in
            guard let id = node["id"] as? String, let key = node["key"] as? String else { return nil }
            let states = ((node["states"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { state -> LinearState? in
                guard let id = state["id"] as? String, let name = state["name"] as? String else { return nil }
                return LinearState(id: id, name: name, type: state["type"] as? String ?? "",
                                   position: (state["position"] as? NSNumber)?.doubleValue ?? 0)
            }
            return LinearTeam(id: id, key: key, name: node["name"] as? String ?? key, states: states)
        }
    }

    /// The created issue's identifier and link.
    static func createdIssue(from data: Data) -> (identifier: String, url: String)? {
        guard let result = dataObject(data)?["issueCreate"] as? [String: Any], result["success"] as? Bool == true,
              let issue = result["issue"] as? [String: Any], let identifier = issue["identifier"] as? String else { return nil }
        return (identifier, issue["url"] as? String ?? "")
    }

    static func succeeded(_ data: Data, operation: String) -> Bool {
        (dataObject(data)?[operation] as? [String: Any])?["success"] as? Bool == true
    }

    /// A team's first state of a type: "started" for Start, "completed" for Done.
    static func state(ofType type: String, in team: LinearTeam) -> LinearState? {
        team.states.filter { $0.type == type }.min { $0.position < $1.position }
    }

    /// Issue ids like "ENG-123" in text, optionally only for known team keys.
    static func identifiers(in text: String, teamKeys: Set<String> = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\b([A-Z][A-Z0-9]{1,9})-([0-9]{1,6})\\b") else { return [] }
        var found: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let key = Range(match.range(at: 1), in: text) else { continue }
            let identifier = String(text[range])
            if (teamKeys.isEmpty || teamKeys.contains(String(text[key]))) && !found.contains(identifier) {
                found.append(identifier)
            }
        }
        return found
    }

    /// Issues whose state changed since the last fetch.
    static func moves(from old: [LinearIssue], to new: [LinearIssue]) -> [(issue: LinearIssue, from: String)] {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return new.compactMap { issue in
            guard let previous = before[issue.id], previous.stateName != issue.stateName else { return nil }
            return (issue, previous.stateName)
        }
    }

    static func loop(for issue: LinearIssue, project: String?) -> OrbitLoop {
        OrbitLoop(id: "linear:\(issue.id)", kind: .linear, title: "\(issue.identifier) \(issue.title)",
                  detail: [issue.stateName, issue.projectName ?? issue.teamName].filter { !$0.isEmpty }.joined(separator: " · "),
                  date: issue.updatedAt ?? .distantPast, project: project, url: issue.url, issueID: issue.id)
    }

    /// The Orbit project an issue belongs to: its Linear project's name, else its team's.
    static func project(for issue: LinearIssue, projects: [OrbitProject]) -> String? {
        for name in [issue.projectName, issue.teamName, issue.teamKey].compactMap({ $0 }) {
            let key = OrbitPolicy.key(name)
            if let match = projects.first(where: { $0.id == key }) { return match.id }
        }
        return nil
    }
}
