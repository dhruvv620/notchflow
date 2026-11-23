// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Orbit: projects and people that build themselves from what you already do
// (terminal commands, AI agents, builds, messages, promises), written to an
// Obsidian vault as plain markdown. Everything here is pure so it can be
// tested on its own (tests/OrbitRegression.swift).

/// One thing that happened, tied to a project and/or a person.
struct OrbitEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case command, agent, build, message, promise, focus, note
        var symbol: String {
            switch self {
            case .command: return "terminal"
            case .agent: return "sparkles"
            case .build: return "hammer"
            case .message: return "message"
            case .promise: return "hand.raised"
            case .focus: return "eye"
            case .note: return "note.text"
            }
        }
    }
    var id: UUID = UUID()
    let date: Date
    let kind: Kind
    let text: String
    /// OrbitProject.id
    var project: String?
    /// OrbitPerson.id
    var person: String?
    var url: String?
}

struct OrbitProject: Codable, Equatable, Identifiable, Sendable {
    /// Stable key: the lowercased name.
    let id: String
    var name: String
    /// The folder it lives in, when known (from the terminal or an agent).
    var root: String?
    let created: Date
    var lastActive: Date
    /// Minutes of focus counted by time tracking, per day ("2026-11-23").
    var minutesByDay: [String: Int] = [:]
    /// Person id → how often they came up with this project.
    var people: [String: Int] = [:]
    /// Pinned by the user: kept even when idle.
    var pinned = false

    var totalMinutes: Int { minutesByDay.values.reduce(0, +) }
}

struct OrbitPerson: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var lastSeen: Date
    var messages: Int = 0
    /// Project id → how often they came up with it.
    var projects: [String: Int] = [:]
    /// Where you last talked ("WhatsApp", "Messages", ...).
    var lastApp: String?
}

/// Everything Orbit keeps, saved as one JSON file.
struct OrbitState: Codable, Equatable, Sendable {
    var projects: [String: OrbitProject] = [:]
    var people: [String: OrbitPerson] = [:]
    var events: [OrbitEvent] = []
    /// Loop id → when it was marked done (Loops).
    var dismissedLoops: [String: Date] = [:]
    /// Loop id → hidden until.
    var snoozedLoops: [String: Date] = [:]
    var version = 1

    static let empty = OrbitState()

    init() {}

    /// Every field is optional on disk, so older files still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([String: OrbitProject].self, forKey: .projects) ?? [:]
        people = try container.decodeIfPresent([String: OrbitPerson].self, forKey: .people) ?? [:]
        events = try container.decodeIfPresent([OrbitEvent].self, forKey: .events) ?? []
        dismissedLoops = try container.decodeIfPresent([String: Date].self, forKey: .dismissedLoops) ?? [:]
        snoozedLoops = try container.decodeIfPresent([String: Date].self, forKey: .snoozedLoops) ?? [:]
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

enum OrbitPolicy {
    // MARK: Limits (keep memory small)

    static let maxEvents = 1500
    static let maxEventsPerProjectNote = 40
    static let maxTextLength = 140
    /// Projects idle this long (and not pinned) drop out of the tab.
    static let staleAfter: TimeInterval = 30 * 86_400

    // MARK: Projects from folders

    /// Files or folders that mark the top of a project.
    static let rootMarkers = [".git", "Package.swift", "package.json", "Cargo.toml", "go.mod",
                              "pyproject.toml", "Gemfile", "pom.xml", "build.gradle", "Makefile", ".obsidian"]

    /// The project folder that holds `path`: the nearest folder (itself or a
    /// parent) with a project marker, never the home folder or above it.
    static func projectRoot(for path: String, home: String, exists: (String) -> Bool) -> String? {
        var current = (path as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        guard !current.isEmpty, current.hasPrefix("/") else { return nil }
        while current != "/" && current != home {
            if rootMarkers.contains(where: { exists((current as NSString).appendingPathComponent($0)) }) {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }

    /// A display name for a project folder.
    static func projectName(root: String) -> String {
        let name = (root as NSString).lastPathComponent
        return name.isEmpty ? root : name
    }

    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Text matching

    /// The known project a piece of text talks about ("fix the notchflow
    /// build" → NotchFlow). Whole words only, longest name first.
    static func project(mentionedIn text: String, names: [String]) -> String? {
        let words = Set(tokens(text))
        let lowered = text.lowercased()
        for name in names.sorted(by: { $0.count > $1.count }) {
            let parts = tokens(name)
            guard !parts.isEmpty, parts.joined().count >= 3 else { continue }
            if parts.count == 1 ? words.contains(parts[0]) : lowered.contains(parts.joined(separator: " ")) {
                return name
            }
        }
        return nil
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Short, single-line text for an event.
    static func clip(_ text: String, to limit: Int = maxTextLength) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }

    // MARK: Terminal

    /// Commands too small to be worth remembering.
    static let quietCommands: Set<String> = ["ls", "cd", "pwd", "clear", "cat", "less", "more", "man", "echo", "which",
                                             "exa", "eza", "tree", "head", "tail", "open", "z", "history", "top", "htop",
                                             "vim", "nvim", "nano", "vi", "emacs", "zsh", "bash", "fish", "sleep"]

    static func isNoteworthy(command: String, duration: TimeInterval) -> Bool {
        let name = command.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, !quietCommands.contains(name) else { return false }
        return duration >= 2
    }

    static func describe(command: String, duration: TimeInterval) -> String {
        "Ran \(command) (\(durationText(duration)))"
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }

    // MARK: People

    /// Apps whose notification title is a person.
    static let messagingApps: Set<String> = ["whatsapp", "messages", "slack", "telegram", "discord", "signal",
                                             "microsoft teams", "teams", "mail", "messenger"]

    static func isMessagingApp(_ name: String) -> Bool { messagingApps.contains(name.lowercased()) }

    /// A sender name worth a person note: not a number-only handle, not a group summary.
    static func personName(fromTitle title: String) -> String? {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Ana (2 messages)" / "Ana • Team chat"
        for separator in [" (", " • ", " · ", " @ ", ": "] {
            if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
        }
        name = name.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2, name.count <= 40 else { return nil }
        guard name.rangeOfCharacter(from: .letters) != nil else { return nil }
        let lowered = name.lowercased()
        let generic = ["new message", "message", "messages", "notification", "you", "unknown", "missed call"]
        guard !generic.contains(lowered), !lowered.hasSuffix(" messages") else { return nil }
        return name
    }

    // MARK: Updating state

    /// Adds an event, keeps project/person stats in step, and trims the log.
    static func record(_ event: OrbitEvent, in state: inout OrbitState) {
        var event = event
        event = OrbitEvent(id: event.id, date: event.date, kind: event.kind, text: clip(event.text),
                           project: event.project, person: event.person, url: event.url)
        if let id = event.project, var project = state.projects[id] {
            project.lastActive = max(project.lastActive, event.date)
            if let person = event.person { project.people[person, default: 0] += 1 }
            state.projects[id] = project
        }
        if let id = event.person, var person = state.people[id] {
            person.lastSeen = max(person.lastSeen, event.date)
            if event.kind == .message { person.messages += 1 }
            if let project = event.project { person.projects[project, default: 0] += 1 }
            state.people[id] = person
        }
        state.events.append(event)
        if state.events.count > maxEvents {
            state.events.removeFirst(state.events.count - maxEvents)
        }
    }

    /// Finds or makes the project for a folder or name. Returns its id.
    @discardableResult
    static func upsertProject(name: String, root: String?, at date: Date, in state: inout OrbitState) -> String {
        if let root, let existing = state.projects.values.first(where: { $0.root == root }) {
            return existing.id
        }
        let id = key(name)
        if var project = state.projects[id] {
            if project.root == nil, let root { project.root = root }
            project.lastActive = max(project.lastActive, date)
            state.projects[id] = project
        } else {
            state.projects[id] = OrbitProject(id: id, name: name, root: root, created: date, lastActive: date)
        }
        return id
    }

    @discardableResult
    static func upsertPerson(name: String, app: String?, at date: Date, in state: inout OrbitState) -> String {
        let id = key(name)
        if var person = state.people[id] {
            person.lastSeen = max(person.lastSeen, date)
            if let app { person.lastApp = app }
            state.people[id] = person
        } else {
            state.people[id] = OrbitPerson(id: id, name: name, lastSeen: date, lastApp: app)
        }
        return id
    }

    static func addFocus(minutes: Int, project id: String, day: String, in state: inout OrbitState) {
        guard minutes > 0, var project = state.projects[id] else { return }
        project.minutesByDay[day, default: 0] += minutes
        // Keep about two months of days.
        if project.minutesByDay.count > 62 {
            for old in project.minutesByDay.keys.sorted().prefix(project.minutesByDay.count - 62) {
                project.minutesByDay[old] = nil
            }
        }
        state.projects[id] = project
    }

    /// Projects for the tab: pinned first, then most recently active, without stale ones.
    static func activeProjects(_ state: OrbitState, now: Date) -> [OrbitProject] {
        state.projects.values
            .filter { $0.pinned || now.timeIntervalSince($0.lastActive) < staleAfter }
            .sorted { ($0.pinned ? 1 : 0, $0.lastActive) > ($1.pinned ? 1 : 0, $1.lastActive) }
    }

    static func events(for project: String, in state: OrbitState, limit: Int) -> [OrbitEvent] {
        Array(state.events.lazy.filter { $0.project == project }.suffix(limit).reversed())
    }

    static func events(forPerson person: String, in state: OrbitState, limit: Int) -> [OrbitEvent] {
        Array(state.events.lazy.filter { $0.person == person }.suffix(limit).reversed())
    }

    static func topPeople(of project: OrbitProject, in state: OrbitState, limit: Int = 6) -> [OrbitPerson] {
        project.people.sorted { $0.value > $1.value }.prefix(limit).compactMap { state.people[$0.key] }
    }

    // MARK: Days

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Obsidian vault

    static let managedStart = "<!-- orbit:start (NotchFlow updates this part; write your own notes outside it) -->"
    static let managedEnd = "<!-- orbit:end -->"

    /// A safe file name for a note.
    static func fileName(_ title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let cleaned = title.components(separatedBy: banned).joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(80))
    }

    static func link(_ title: String) -> String { "[[\(fileName(title))]]" }

    /// Puts the generated part into a note, keeping everything the user wrote
    /// outside the managed block.
    static func merge(existing: String?, managed: String, header: String) -> String {
        let block = "\(managedStart)\n\(managed.trimmingCharacters(in: .newlines))\n\(managedEnd)"
        guard let existing, !existing.isEmpty else {
            return "\(header)\n\(block)\n\n## Notes\n\n"
        }
        if let start = existing.range(of: managedStart),
           let end = existing.range(of: managedEnd, range: start.upperBound..<existing.endIndex) {
            return existing.replacingCharacters(in: start.lowerBound..<end.upperBound, with: block)
        }
        // A note made by the user: add the block at the end.
        return existing.hasSuffix("\n") ? existing + "\n" + block + "\n" : existing + "\n\n" + block + "\n"
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func line(_ event: OrbitEvent, state: OrbitState, calendar: Calendar,
                             showProject: Bool, showPerson: Bool, showDay: Bool) -> String {
        var text = "- "
        text += showDay ? "\(dayKey(event.date, calendar: calendar)) \(time(event.date, calendar: calendar))" : time(event.date, calendar: calendar)
        text += " \(event.kind.rawValue): \(event.text)"
        if showProject, let id = event.project, let project = state.projects[id] { text += " · \(link(project.name))" }
        if showPerson, let id = event.person, let person = state.people[id] { text += " · \(link(person.name))" }
        if let url = event.url, !url.isEmpty { text += " ([open](\(url)))" }
        return text
    }

    static func projectNoteHeader(_ project: OrbitProject) -> String {
        var lines = ["---", "type: project", "orbit: \(project.id)"]
        if let root = project.root { lines.append("folder: \"\(root)\"") }
        lines += ["tags: [project]", "---", "", "# \(project.name)", ""]
        return lines.joined(separator: "\n")
    }

    static func projectNote(_ project: OrbitProject, state: OrbitState, calendar: Calendar = .current) -> String {
        var out: [String] = []
        out.append("Last active: \(dayKey(project.lastActive, calendar: calendar))")
        if let root = project.root { out.append("Folder: `\(root)`") }
        let hours = Double(project.totalMinutes) / 60
        if project.totalMinutes > 0 { out.append(String(format: "Focus: %.1f h tracked", hours)) }
        let people = topPeople(of: project, in: state)
        if !people.isEmpty {
            out.append("")
            out.append("## People")
            out += people.map { "- \(link($0.name))" }
        }
        let events = events(for: project.id, in: state, limit: maxEventsPerProjectNote)
        if !events.isEmpty {
            out.append("")
            out.append("## Timeline")
            out += events.map { line($0, state: state, calendar: calendar, showProject: false, showPerson: true, showDay: true) }
        }
        return out.joined(separator: "\n")
    }

    static func personNoteHeader(_ person: OrbitPerson) -> String {
        ["---", "type: person", "orbit: \(person.id)", "tags: [person]", "---", "", "# \(person.name)", ""].joined(separator: "\n")
    }

    static func personNote(_ person: OrbitPerson, state: OrbitState, calendar: Calendar = .current) -> String {
        var out = ["Last talked: \(dayKey(person.lastSeen, calendar: calendar))" + (person.lastApp.map { " on \($0)" } ?? "")]
        let projects = person.projects.sorted { $0.value > $1.value }.prefix(8).compactMap { state.projects[$0.key] }
        if !projects.isEmpty {
            out.append("")
            out.append("## Projects")
            out += projects.map { "- \(link($0.name))" }
        }
        let events = events(forPerson: person.id, in: state, limit: 25)
        if !events.isEmpty {
            out.append("")
            out.append("## Recent")
            out += events.map { line($0, state: state, calendar: calendar, showProject: true, showPerson: false, showDay: true) }
        }
        return out.joined(separator: "\n")
    }

    static func dailyNoteHeader(day: String) -> String {
        ["---", "type: daily", "date: \(day)", "tags: [daily]", "---", "", "# \(day)", ""].joined(separator: "\n")
    }

    /// The day's journal: what happened, grouped by project.
    static func dailyNote(day: String, state: OrbitState, calendar: Calendar = .current) -> String {
        let todays = state.events.filter { dayKey($0.date, calendar: calendar) == day }
        guard !todays.isEmpty else { return "Nothing recorded yet." }
        var out: [String] = []
        let grouped = Dictionary(grouping: todays) { $0.project ?? "" }
        let order = grouped.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return (grouped[a]?.count ?? 0) > (grouped[b]?.count ?? 0)
        }
        for key in order {
            let title = key.isEmpty ? "Other" : (state.projects[key].map { link($0.name) } ?? key)
            out.append("## \(title)")
            let minutes = state.projects[key]?.minutesByDay[day] ?? 0
            if minutes > 0 { out.append("Focus: \(minutes) min") }
            out += (grouped[key] ?? []).map { line($0, state: state, calendar: calendar, showProject: false, showPerson: true, showDay: false) }
            out.append("")
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// `obsidian://open?path=...` for a note, so it opens in Obsidian.
    static func obsidianURL(forFile path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
}
