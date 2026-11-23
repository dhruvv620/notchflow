// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct OrbitRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "OrbitRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = OrbitPolicy
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18

        // Project roots
        let markers: Set<String> = ["/Users/d/code/notchflow/.git", "/Users/d/.git", "/Users/d/code/site/package.json"]
        let exists: (String) -> Bool = { markers.contains($0) }
        try require(P.projectRoot(for: "/Users/d/code/notchflow/DynamicIsland/helpers", home: "/Users/d", exists: exists) == "/Users/d/code/notchflow", "Nearest root")
        try require(P.projectRoot(for: "/Users/d/code/notchflow", home: "/Users/d", exists: exists) == "/Users/d/code/notchflow", "Root itself")
        try require(P.projectRoot(for: "/Users/d/Downloads", home: "/Users/d", exists: exists) == nil, "Never the home folder")
        try require(P.projectRoot(for: "/Users/d", home: "/Users/d", exists: exists) == nil, "Home itself")
        try require(P.projectRoot(for: "/Users/d/code/site/src/", home: "/Users/d", exists: exists) == "/Users/d/code/site", "package.json")
        try require(P.projectRoot(for: "relative/path", home: "/Users/d", exists: exists) == nil, "Relative paths")
        try require(P.projectName(root: "/Users/d/code/notchflow") == "notchflow", "Name")

        // Mentions
        try require(P.project(mentionedIn: "Can you fix the NotchFlow build?", names: ["NotchFlow", "Site"]) == "NotchFlow", "Mention")
        try require(P.project(mentionedIn: "the website is down", names: ["site"]) == nil, "Whole words only")
        try require(P.project(mentionedIn: "ship the Acme Web redesign", names: ["Acme", "Acme Web"]) == "Acme Web", "Longest first")
        try require(P.project(mentionedIn: "go go", names: ["go"]) == nil, "Too short")

        // Commands
        try require(!P.isNoteworthy(command: "ls", duration: 10), "Quiet command")
        try require(!P.isNoteworthy(command: "cargo", duration: 1), "Too quick")
        try require(P.isNoteworthy(command: "cargo", duration: 12), "Build")
        try require(P.describe(command: "swift", duration: 125) == "Ran swift (2m)", "Describe: \(P.describe(command: "swift", duration: 125))")
        try require(P.durationText(3725) == "1h 2m", "Hours")

        // People
        try require(P.personName(fromTitle: "Ana (2 messages)") == "Ana", "Count suffix")
        try require(P.personName(fromTitle: "Ravi • Team") == "Ravi", "Group suffix")
        try require(P.personName(fromTitle: "+1 555 0100") == nil, "Numbers only")
        try require(P.personName(fromTitle: "New message") == nil, "Generic")
        try require(P.isMessagingApp("WhatsApp") && !P.isMessagingApp("Xcode"), "Messaging apps")

        // State
        var state = OrbitState.empty
        let project = P.upsertProject(name: "notchflow", root: "/Users/d/code/notchflow", at: now, in: &state)
        try require(project == "notchflow", "Project id")
        try require(P.upsertProject(name: "other name", root: "/Users/d/code/notchflow", at: now, in: &state) == "notchflow", "Same root, same project")
        let ana = P.upsertPerson(name: "Ana", app: "WhatsApp", at: now, in: &state)
        P.record(OrbitEvent(date: now, kind: .message, text: "Is the notch build ready?", project: project, person: ana), in: &state)
        P.record(OrbitEvent(date: now.addingTimeInterval(60), kind: .command, text: "Ran swift (2m)", project: project), in: &state)
        try require(state.people[ana]?.messages == 1 && state.people[ana]?.projects[project] == 1, "Person stats")
        try require(state.projects[project]?.people[ana] == 1, "Project people")
        try require(P.events(for: project, in: state, limit: 5).first?.kind == .command, "Newest first")
        P.addFocus(minutes: 25, project: project, day: "2026-11-18", in: &state)
        try require(state.projects[project]?.totalMinutes == 25, "Focus")
        for index in 0..<(P.maxEvents + 10) {
            P.record(OrbitEvent(date: now, kind: .note, text: "n\(index)"), in: &state)
        }
        try require(state.events.count == P.maxEvents, "Capped events")
        try require(P.clip(String(repeating: "a", count: 300)).count == P.maxTextLength, "Clip")

        _ = P.upsertProject(name: "Old", root: nil, at: now.addingTimeInterval(-40 * 86_400), in: &state)
        try require(P.activeProjects(state, now: now).map(\.id) == ["notchflow"], "Stale projects hidden")
        state.projects["old"]?.pinned = true
        try require(P.activeProjects(state, now: now).first?.id == "old", "Pinned first")

        // Codable round trip
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(OrbitState.self, from: data)
        try require(decoded == state, "Round trip")

        // Vault
        try require(P.fileName("a/b: c?") == "a b c", "File name: \(P.fileName("a/b: c?"))")
        try require(P.fileName("..") == "Untitled", "Empty name")
        let fresh = P.merge(existing: nil, managed: "Body", header: "# T\n")
        try require(fresh.contains(P.managedStart) && fresh.contains("Body") && fresh.contains("## Notes"), "New note")
        let edited = fresh + "My own thoughts\n"
        let updated = P.merge(existing: edited, managed: "New body", header: "# T\n")
        try require(updated.contains("New body") && !updated.contains("\nBody\n") && updated.contains("My own thoughts"), "Keeps user text")
        let userNote = P.merge(existing: "Written by me", managed: "X", header: "")
        try require(userNote.hasPrefix("Written by me") && userNote.contains(P.managedEnd), "Adds block to a user note")

        var small = OrbitState.empty
        let p = P.upsertProject(name: "NotchFlow", root: "/r", at: now, in: &small)
        let ravi = P.upsertPerson(name: "Ravi", app: "Slack", at: now, in: &small)
        P.record(OrbitEvent(date: now, kind: .agent, text: "Claude finished: fix tabs", project: p, person: ravi), in: &small)
        let note = P.projectNote(small.projects[p]!, state: small, calendar: calendar)
        try require(note.contains("[[Ravi]]") && note.contains("agent: Claude finished: fix tabs"), "Project note: \(note)")
        let personNote = P.personNote(small.people[ravi]!, state: small, calendar: calendar)
        try require(personNote.contains("[[NotchFlow]]") && personNote.contains("on Slack"), "Person note: \(personNote)")
        let day = P.dayKey(now, calendar: calendar)
        try require(day == "2026-11-18", "Day key \(day)")
        let daily = P.dailyNote(day: day, state: small, calendar: calendar)
        try require(daily.hasPrefix("## [[NotchFlow]]"), "Daily note: \(daily)")
        try require(P.dailyNote(day: "2001-01-01", state: small, calendar: calendar) == "Nothing recorded yet.", "Empty day")
        try require(P.obsidianURL(forFile: "/v/Projects/A B.md")?.absoluteString == "obsidian://open?path=/v/Projects/A%20B.md", "Obsidian URL")

        print("Orbit: all checks passed")
    }
}
