// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Orbit Team, Scenes and the daily brief. Pure, tested in tests/OrbitRegression.swift.

/// A one-click setup for a kind of work: a workspace, quiet time, a terminal
/// in the project, and an agent started on a task.
struct OrbitScene: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var symbol = "sparkles.rectangle.stack"
    /// OrbitProject.id
    var project: String?
    /// Workspace.id to open.
    var workspace: UUID?
    /// Hold notifications this long (0 = don't).
    var quietMinutes = 0
    /// Open a Terminal tab in the project's folder.
    var openTerminal = false
    /// Start the default AI agent in the project with this task (empty = don't).
    var agentTask = ""
}

/// The morning summary.
struct OrbitBrief: Codable, Equatable, Sendable {
    let day: String
    let headline: String
    let lines: [String]
    let created: Date
}

enum OrbitTeamPolicy {
    // MARK: Hand-off

    /// The task an agent gets when a loop is handed to it.
    static func handoffPrompt(title: String, detail: String, url: String?,
                              description: String? = nil, buildFailure: String? = nil, history: [String] = []) -> String {
        var parts = ["Task: \(title)"]
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append("Context: \(trimmed)") }
        if let url, !url.isEmpty { parts.append("Link: \(url)") }
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            let clipped = description.count > 2000 ? String(description.prefix(2000)) + "…" : description
            parts.append("Description:\n\(clipped)")
        }
        if let buildFailure, !buildFailure.isEmpty { parts.append("The last build failed: \(buildFailure)") }
        if !history.isEmpty {
            parts.append("Recently in this project:\n" + history.prefix(8).map { "- \($0)" }.joined(separator: "\n"))
        }
        parts.append("When you're done, sum up what you changed in a few lines.")
        return parts.joined(separator: "\n")
    }

    /// A project's recent timeline as short lines for an agent.
    static func history(for project: String, in state: OrbitState, calendar: Calendar = .current) -> [String] {
        OrbitPolicy.events(for: project, in: state, limit: 8).map {
            "\(OrbitPolicy.dayKey($0.date, calendar: calendar)) \($0.kind.rawValue): \($0.text)"
        }
    }

    /// "Working 12m", "Waiting 3m", "Done 1h ago".
    static func status(working: Bool, waiting: Bool, since: Date?, now: Date) -> String {
        let elapsed = since.map { OrbitPolicy.durationText(max(0, now.timeIntervalSince($0))) }
        if working { return elapsed.map { "Working \($0)" } ?? "Working" }
        if waiting { return elapsed.map { "Waiting \($0)" } ?? "Waiting for you" }
        return elapsed.map { "Done \($0) ago" } ?? "Idle"
    }

    // MARK: Scenes

    /// What running a scene will do, for its card.
    static func steps(of scene: OrbitScene, projectName: String?, workspaceName: String?) -> [String] {
        var steps: [String] = []
        if let workspaceName { steps.append("Open \(workspaceName)") }
        if scene.quietMinutes > 0 { steps.append("Quiet for \(scene.quietMinutes) min") }
        if scene.openTerminal, let projectName { steps.append("Terminal in \(projectName)") }
        let task = scene.agentTask.trimmingCharacters(in: .whitespacesAndNewlines)
        if !task.isEmpty { steps.append("Agent: \(OrbitPolicy.clip(task, to: 40))") }
        return steps.isEmpty ? ["Nothing set up yet"] : steps
    }

    /// A first scene for a busy project.
    static func starterScene(for project: OrbitProject) -> OrbitScene {
        OrbitScene(name: "Deep work: \(project.name)", symbol: "scope", project: project.id,
                   quietMinutes: 50, openTerminal: project.root != nil)
    }

    // MARK: Daily brief

    struct Meeting: Sendable {
        let title: String
        let start: Date
        let allDay: Bool
    }

    /// The next time the brief is due: today at `hour` if that's still ahead, else tomorrow.
    static func nextBriefDate(after now: Date, hour: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }

    /// Whether today's brief is owed: past the hour and not given yet today.
    static func briefIsDue(lastDay: String, now: Date, hour: Int, calendar: Calendar = .current) -> Bool {
        let day = OrbitPolicy.dayKey(now, calendar: calendar)
        return lastDay != day && calendar.component(.hour, from: now) >= hour
    }

    static func brief(state: OrbitState, loops: [OrbitLoop], meetings: [Meeting], now: Date,
                      calendar: Calendar = .current) -> OrbitBrief {
        let day = OrbitPolicy.dayKey(now, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { OrbitPolicy.dayKey($0, calendar: calendar) } ?? ""
        var lines: [String] = []

        // Yesterday, by project.
        let recent = state.events.filter { OrbitPolicy.dayKey($0.date, calendar: calendar) == yesterday && $0.project != nil }
        let counts = Dictionary(grouping: recent) { $0.project ?? "" }.mapValues(\.count)
        let ranked = Set(counts.keys).union(state.projects.values.filter { ($0.minutesByDay[yesterday] ?? 0) > 0 }.map(\.id))
            .compactMap { state.projects[$0] }
            .sorted { (counts[$0.id] ?? 0, $0.minutesByDay[yesterday] ?? 0) > (counts[$1.id] ?? 0, $1.minutesByDay[yesterday] ?? 0) }
        for project in ranked.prefix(3) {
            var parts: [String] = []
            if let count = counts[project.id] { parts.append("\(count) update\(count == 1 ? "" : "s")") }
            if let minutes = project.minutesByDay[yesterday], minutes > 0 { parts.append(String(format: "%.1fh focus", Double(minutes) / 60)) }
            lines.append("Yesterday on \(project.name): \(parts.joined(separator: ", "))")
        }

        // Meetings today.
        let todays = meetings.filter { calendar.isDate($0.start, inSameDayAs: now) && !$0.allDay }.sorted { $0.start < $1.start }
        if let first = todays.first(where: { $0.start >= now }) ?? todays.first {
            let parts = calendar.dateComponents([.hour, .minute], from: first.start)
            let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
            lines.append("\(todays.count) meeting\(todays.count == 1 ? "" : "s") today, next at \(time): \(first.title)")
        }

        // What's open.
        let overdue = loops.filter { ($0.kind == .promise) && ($0.due.map { $0 < now } ?? false) }.count
        let agents = loops.filter { $0.kind == .agent }.count
        let issues = loops.filter { $0.kind == .linear }.count
        let replies = loops.filter { $0.kind == .message }.count
        let reviews = loops.filter { $0.kind == .review }.count
        var open: [String] = []
        if reviews > 0 { open.append("\(reviews) change\(reviews == 1 ? "" : "s") to review") }
        if agents > 0 { open.append("\(agents) agent\(agents == 1 ? "" : "s") waiting") }
        if overdue > 0 { open.append("\(overdue) overdue promise\(overdue == 1 ? "" : "s")") }
        if replies > 0 { open.append("\(replies) repl\(replies == 1 ? "y" : "ies") owed") }
        if issues > 0 { open.append("\(issues) Linear issue\(issues == 1 ? "" : "s")") }
        if !open.isEmpty { lines.append("Open: " + open.joined(separator: ", ")) }
        if let top = loops.first { lines.append("Start with: \(top.title)") }

        let headline: String
        if loops.isEmpty && todays.isEmpty {
            headline = "A clear day"
        } else {
            headline = "\(loops.count) open loop\(loops.count == 1 ? "" : "s")" + (todays.isEmpty ? "" : ", \(todays.count) meeting\(todays.count == 1 ? "" : "s")")
        }
        return OrbitBrief(day: day, headline: headline, lines: lines.isEmpty ? ["Nothing from yesterday yet."] : lines, created: now)
    }

    /// The brief as a daily note section.
    static func markdown(_ brief: OrbitBrief) -> String {
        (["## Brief", "**\(brief.headline)**"] + brief.lines.map { "- \($0)" }).joined(separator: "\n")
    }
}
