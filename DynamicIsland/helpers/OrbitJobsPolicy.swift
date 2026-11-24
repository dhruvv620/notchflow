// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Background hand-offs: an agent works on a loop out of sight, in its own
// copy of the project (a git worktree), and comes back with changes to
// review. Pure, tested in tests/OrbitRegression.swift.

struct OrbitDiffStat: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let path: String
        let added: Int
        let removed: Int
    }
    var files: [File] = []
    var added: Int { files.reduce(0) { $0 + $1.added } }
    var removed: Int { files.reduce(0) { $0 + $1.removed } }
    var isEmpty: Bool { files.isEmpty }
    /// "3 files · +40 −12"
    var summary: String {
        guard !files.isEmpty else { return "No changes" }
        return "\(files.count) file\(files.count == 1 ? "" : "s") · +\(added) −\(removed)"
    }
}

struct OrbitJob: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case running, review, failed, applied, committed, discarded
        var isOpen: Bool { self == .running || self == .review || self == .failed }
    }
    var id = UUID()
    /// AgentHookPolicy.LaunchAgent raw value ("claude", "codex").
    let agent: String
    let title: String
    var prompt: String
    var loopID: String?
    var issueID: String?
    var url: String?
    var project: String?
    /// The folder you asked for (inside your project).
    let folder: String
    /// The repository's top folder, when it's a git project.
    var repoRoot: String?
    /// Where the agent works: a worktree, or `folder` itself without git.
    var workFolder: String
    var branch: String?
    var baseCommit: String?
    var state: State = .running
    var sessionID: String?
    var summary = ""
    var error: String?
    var changes = OrbitDiffStat()
    let started: Date
    var finished: Date?
}

enum OrbitJobsPolicy {
    /// Agents that can run without a terminal.
    static let backgroundAgents: Set<String> = ["claude", "codex"]

    static func slug(_ text: String, limit: Int = 32) -> String {
        let lowered = text.lowercased()
        var out = ""
        var lastDash = true
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
            if out.count >= limit { break }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "task" : trimmed
    }

    /// "orbit/fix-settings-typo-1a2b3c"
    static func branchName(title: String, id: UUID) -> String {
        "orbit/\(slug(title))-\(id.uuidString.prefix(6).lowercased())"
    }

    /// Where a job's worktree lives.
    static func worktreePath(base: String, project: String, id: UUID) -> String {
        (base as NSString).appendingPathComponent("\(slug(project, limit: 24))-\(id.uuidString.prefix(8).lowercased())")
    }

    /// The folder inside the worktree that matches the folder you asked for
    /// (an agent asked to work in repo/app works in worktree/app).
    static func workFolder(for folder: String, repoRoot: String, worktree: String) -> String {
        let folder = (folder as NSString).standardizingPath
        let root = (repoRoot as NSString).standardizingPath
        guard folder.hasPrefix(root + "/") else { return worktree }
        return (worktree as NSString).appendingPathComponent(String(folder.dropFirst(root.count + 1)))
    }

    /// The command that runs the agent to the end of its task, printing JSON
    /// events. File edits are allowed without asking: it works in its own copy.
    /// Shell commands still ask in the notch.
    static func command(agent: String, prompt: String, resume sessionID: String? = nil) -> String {
        let q = shellQuoted
        switch agent {
        case "codex":
            if let sessionID { return "codex exec --json --full-auto resume \(q(sessionID)) \(q(prompt))" }
            return "codex exec --json --full-auto \(q(prompt))"
        default:
            let resume = sessionID.map { "--resume \(q($0)) " } ?? ""
            return "claude -p \(resume)--permission-mode acceptEdits --output-format stream-json --verbose \(q(prompt))"
        }
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `git diff --numstat` output ("12\t3\tpath", binary files as "-\t-\tpath").
    static func diffStat(fromNumstat output: String) -> OrbitDiffStat {
        var stat = OrbitDiffStat()
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            stat.files.append(.init(path: String(parts[2]), added: Int(parts[0]) ?? 0, removed: Int(parts[1]) ?? 0))
        }
        return stat
    }

    /// What the agent said at the end, from one streamed JSON line (Claude's
    /// result event, Codex's final agent message).
    static func finalAnswer(fromStreamLine line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        if object["type"] as? String == "result", object["is_error"] as? Bool != true {
            return object["result"] as? String
        }
        if object["type"] as? String == "item.completed", let item = object["item"] as? [String: Any],
           item["type"] as? String == "agent_message" {
            return item["text"] as? String
        }
        return nil
    }

    static func commitMessage(title: String, agentName: String) -> String {
        "\(OrbitPolicy.clip(title, to: 72))\n\nMade by \(agentName) from NotchFlow Orbit."
    }

    /// Jobs worth showing: open ones, then recent closed ones (a day).
    static func visible(_ jobs: [OrbitJob], now: Date) -> [OrbitJob] {
        jobs.filter { $0.state.isOpen || now.timeIntervalSince($0.finished ?? $0.started) < 86_400 }
            .sorted { a, b in
                let rank: (OrbitJob) -> Int = { $0.state == .review ? 0 : $0.state == .running ? 1 : $0.state == .failed ? 2 : 3 }
                return (rank(a), b.started) < (rank(b), a.started)
            }
    }
}
