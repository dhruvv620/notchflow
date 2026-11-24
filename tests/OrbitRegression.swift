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

        // Older files without the Loops fields still load.
        let old = try JSONDecoder().decode(OrbitState.self, from: Data(#"{"projects":{},"people":{},"events":[],"version":1}"#.utf8))
        try require(old.dismissedLoops.isEmpty, "Old file loads")

        // Loops
        typealias L = OrbitLoopsPolicy
        let messages = L.messageLoops([
            .init(app: "WhatsApp", sender: "Ana", text: "first", date: now.addingTimeInterval(-60)),
            .init(app: "WhatsApp", sender: "Ana (2 messages)", text: "second", date: now),
            .init(app: "Slack", sender: "New message", text: "x", date: now),
        ])
        try require(messages.count == 1 && messages[0].title == "Reply to Ana (2 messages)" && messages[0].detail == "WhatsApp: second",
                    "Message loops: \(messages)")
        let agent = OrbitLoop(id: "agent:1", kind: .agent, title: "Claude needs you", date: now.addingTimeInterval(-500))
        let promise = OrbitLoop(id: "promise:1", kind: .promise, title: "Send deck", date: now, due: now.addingTimeInterval(-10))
        let later = OrbitLoop(id: "promise:2", kind: .promise, title: "Call", date: now.addingTimeInterval(10), due: now.addingTimeInterval(3600))
        let issue = OrbitLoop(id: "linear:1", kind: .linear, title: "ENG-1", date: now)
        var shown = L.visible([issue, later, promise, agent, messages[0]], dismissed: [:], snoozed: [:], now: now)
        try require(shown.map(\.id) == ["agent:1", "promise:1", "promise:2", "msg:ana", "linear:1"], "Order: \(shown.map(\.id))")
        shown = L.visible([agent, promise, messages[0]], dismissed: ["msg:ana": now.addingTimeInterval(10)], snoozed: ["agent:1": now.addingTimeInterval(60)], now: now)
        try require(shown.map(\.id) == ["promise:1"], "Dismissed and snoozed: \(shown.map(\.id))")
        shown = L.visible([messages[0]], dismissed: ["msg:ana": now.addingTimeInterval(-30)], snoozed: [:], now: now)
        try require(shown.count == 1, "A newer message reopens the loop")
        try require(L.pruned(["a": now.addingTimeInterval(-40 * 86_400), "b": now], now: now, keepFor: L.dismissalMemory).keys.sorted() == ["b"], "Prune")

        // Linear
        let viewerJSON = #"""
        {"data":{"viewer":{"id":"u1","name":"Dhruv","assignedIssues":{"nodes":[
          {"id":"i1","identifier":"ENG-12","title":"Fix tabs","url":"https://linear.app/x/issue/ENG-12","priority":2,
           "updatedAt":"2026-11-18T10:00:00.000Z","state":{"name":"Todo","type":"unstarted"},
           "team":{"id":"t1","key":"ENG","name":"Engineering"},"project":{"name":"NotchFlow"}},
          {"id":"i2","identifier":"ENG-13","title":"No project","url":"u","priority":0,"updatedAt":null,
           "state":{"name":"In Progress","type":"started"},"team":{"id":"t1","key":"ENG","name":"Engineering"},"project":null}
        ]}}}}
        """#
        let viewer = L.viewer(from: Data(viewerJSON.utf8))
        try require(viewer?.name == "Dhruv" && viewer?.issues.count == 2, "Viewer")
        let first = viewer!.issues[0]
        try require(first.projectName == "NotchFlow" && first.teamKey == "ENG" && first.updatedAt != nil && first.priority == 2, "Issue fields")
        try require(viewer!.issues[1].projectName == nil && viewer!.issues[1].updatedAt == nil, "Nulls")
        try require(L.project(for: first, projects: Array(small.projects.values)) == "notchflow", "Issue project")
        try require(L.loop(for: first, project: nil).detail == "Todo · NotchFlow", "Issue loop")

        let teams = L.teams(from: Data(#"""
        {"data":{"teams":{"nodes":[{"id":"t1","key":"ENG","name":"Engineering","states":{"nodes":[
          {"id":"s3","name":"Done","type":"completed","position":3},{"id":"s2","name":"In Review","type":"started","position":2},
          {"id":"s1","name":"In Progress","type":"started","position":1},{"id":"s0","name":"Todo","type":"unstarted","position":0}]}}]}}}
        """#.utf8))
        try require(teams.count == 1 && teams[0].states.count == 4, "Teams")
        try require(L.state(ofType: "started", in: teams[0])?.id == "s1" && L.state(ofType: "completed", in: teams[0])?.id == "s3", "States")

        try require(L.identifiers(in: "Fix ENG-12 and ENG-12, see OPS-4 and UTF-8", teamKeys: ["ENG", "OPS"]) == ["ENG-12", "OPS-4"], "Identifiers")
        try require(L.identifiers(in: "ENG-12 UTF-8") == ["ENG-12", "UTF-8"], "Identifiers without keys")
        let moved = viewer!.issues.map { $0.id == "i1" ? LinearIssue(id: "i1", identifier: "ENG-12", title: "Fix tabs", url: "", stateName: "In Progress", stateType: "started", teamID: "t1", teamKey: "ENG", teamName: "Engineering", projectName: nil, priority: 2, updatedAt: nil) : $0 }
        let moves = L.moves(from: viewer!.issues, to: moved)
        try require(moves.count == 1 && moves[0].from == "Todo" && moves[0].issue.stateName == "In Progress", "Moves")

        let create = String(decoding: L.createIssueBody(teamID: "t1", title: "Ship it", description: "From Orbit")!, as: UTF8.self)
        try require(create.contains(#""teamId":"t1""#) && create.contains("issueCreate") && create.contains(#""description":"From Orbit""#), "Create body: \(create)")
        let move = String(decoding: L.moveIssueBody(issueID: "i1", stateID: "s3")!, as: UTF8.self)
        try require(move.contains(#""stateId":"s3""#) && move.contains(#""id":"i1""#), "Move body")
        try require(L.createdIssue(from: Data(#"{"data":{"issueCreate":{"success":true,"issue":{"id":"x","identifier":"ENG-14","url":"https://l/ENG-14","title":"t"}}}}"#.utf8))?.identifier == "ENG-14", "Created")
        try require(L.succeeded(Data(#"{"data":{"commentCreate":{"success":true}}}"#.utf8), operation: "commentCreate"), "Succeeded")
        try require(L.error(in: Data(#"{"errors":[{"message":"Authentication required"}]}"#.utf8)) == "Authentication required", "Error")
        try require(L.error(in: Data(#"{"data":{}}"#.utf8)) == nil, "No error")

        // Team
        typealias T = OrbitTeamPolicy
        let prompt = T.handoffPrompt(title: "ENG-12 Fix tabs", detail: "Todo · NotchFlow", url: "https://linear.app/x")
        try require(prompt.hasPrefix("Task: ENG-12 Fix tabs\nContext: Todo · NotchFlow\nLink: https://linear.app/x"), "Prompt: \(prompt)")
        try require(!T.handoffPrompt(title: "A", detail: " ", url: nil).contains("Context"), "No empty context")
        try require(T.status(working: true, waiting: false, since: now.addingTimeInterval(-720), now: now) == "Working 12m", "Working")
        try require(T.status(working: false, waiting: true, since: nil, now: now) == "Waiting for you", "Waiting")
        try require(T.status(working: false, waiting: false, since: now.addingTimeInterval(-3600), now: now) == "Done 1h 0m ago", "Done")

        // Scenes
        var scene = T.starterScene(for: small.projects[p]!)
        try require(scene.quietMinutes == 50 && scene.openTerminal && scene.project == p, "Starter scene")
        scene.agentTask = "Review open PRs"
        try require(T.steps(of: scene, projectName: "NotchFlow", workspaceName: "Coding") == ["Open Coding", "Quiet for 50 min", "Terminal in NotchFlow", "Agent: Review open PRs"], "Steps")
        try require(T.steps(of: OrbitScene(name: "x"), projectName: nil, workspaceName: nil) == ["Nothing set up yet"], "Empty scene")

        // Brief timing
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        try require(T.nextBriefDate(after: nine.addingTimeInterval(-60), hour: 9, calendar: calendar) == nine, "Brief later today")
        try require(T.nextBriefDate(after: nine.addingTimeInterval(60), hour: 9, calendar: calendar) == nine.addingTimeInterval(86_400), "Brief tomorrow")
        try require(T.briefIsDue(lastDay: "", now: nine.addingTimeInterval(60), hour: 9, calendar: calendar), "Due")
        try require(!T.briefIsDue(lastDay: "2026-11-18", now: nine.addingTimeInterval(60), hour: 9, calendar: calendar), "Already given")
        try require(!T.briefIsDue(lastDay: "", now: nine.addingTimeInterval(-60), hour: 9, calendar: calendar), "Too early")

        // Brief content
        var briefState = OrbitState.empty
        let bp = P.upsertProject(name: "NotchFlow", root: "/r", at: now, in: &briefState)
        let yesterdayDate = now.addingTimeInterval(-86_400)
        P.record(OrbitEvent(date: yesterdayDate, kind: .command, text: "Ran swift", project: bp), in: &briefState)
        P.record(OrbitEvent(date: yesterdayDate, kind: .agent, text: "Claude finished", project: bp), in: &briefState)
        P.addFocus(minutes: 90, project: bp, day: P.dayKey(yesterdayDate, calendar: calendar), in: &briefState)
        let overduePromise = OrbitLoop(id: "promise:9", kind: .promise, title: "Send deck", date: nine.addingTimeInterval(-100), due: nine.addingTimeInterval(-60))
        let briefLoops = L.visible([agent, overduePromise, messages[0]], dismissed: [:], snoozed: [:], now: nine)
        let meeting = T.Meeting(title: "Standup", start: nine.addingTimeInterval(3600), allDay: false)
        let brief = T.brief(state: briefState, loops: briefLoops, meetings: [meeting, T.Meeting(title: "Holiday", start: nine, allDay: true)], now: nine, calendar: calendar)
        try require(brief.headline == "3 open loops, 1 meeting", "Headline: \(brief.headline)")
        try require(brief.lines.contains("Yesterday on NotchFlow: 2 updates, 1.5h focus"), "Yesterday: \(brief.lines)")
        try require(brief.lines.contains("1 meeting today, next at 10:00: Standup"), "Meetings: \(brief.lines)")
        try require(brief.lines.contains("Open: 1 agent waiting, 1 overdue promise, 1 reply owed"), "Open: \(brief.lines)")
        try require(brief.lines.last == "Start with: Claude needs you", "Start with")
        try require(T.brief(state: .empty, loops: [], meetings: [], now: now, calendar: calendar).headline == "A clear day", "Clear day")
        briefState.lastBrief = brief
        let dailyWithBrief = P.dailyNote(day: brief.day, state: briefState, calendar: calendar)
        try require(dailyWithBrief.hasPrefix("## Brief\n**3 open loops, 1 meeting**"), "Brief in daily note: \(dailyWithBrief)")
        let briefData = try JSONEncoder().encode(briefState)
        let briefDecoded = try JSONDecoder().decode(OrbitState.self, from: briefData)
        try require(briefDecoded == briefState, "Brief round trip")

        // People: pinned only
        var pins = OrbitState.empty
        let pp = P.upsertProject(name: "NotchFlow", root: "/r", at: now, in: &pins)
        P.record(OrbitEvent(date: now, kind: .message, text: "hi", person: "stranger"), in: &pins)
        try require(pins.events.last?.person == nil && pins.people.isEmpty, "Unpinned senders get no link or page")
        try require(P.pinnedPerson(named: "Ron", in: pins) == nil, "Not pinned yet")
        let ron = P.pinPerson(name: "Ron", app: "WhatsApp", at: now, in: &pins)
        try require(P.pinnedPerson(named: " ron ", in: pins) == ron, "Pinned")
        P.record(OrbitEvent(date: now, kind: .message, text: "Message on WhatsApp", person: ron), in: &pins)
        P.record(OrbitEvent(date: now, kind: .message, text: "the NotchFlow build", project: pp, person: ron), in: &pins)
        try require(pins.projects[pp]?.people[ron] == 1, "Project link")
        P.unpinPerson(ron, in: &pins)
        try require(pins.people.isEmpty && pins.projects[pp]?.people.isEmpty == true, "Unpinned")
        try require(!pins.events.contains { $0.text == "Message on WhatsApp" } && pins.events.contains { $0.text == "the NotchFlow build" && $0.person == nil },
                    "Unpin drops bare messages, keeps project history")
        var v1 = small
        v1.version = 1
        let v2 = P.migrated(v1)
        try require(v2.people.isEmpty && v2.version == 2, "Old automatic people cleared")
        try require(P.migrated(v2) == v2, "Migrates once")
        try require(OrbitState.empty.version == 2, "New state is current")

        // Obsidian vaults
        let vaults = P.obsidianVaults(from: Data(#"{"vaults":{"a1":{"path":"/Users/dv/Notes","ts":1,"open":true},"b2":{"path":"/Users/dv/Orbit/Obsidian/"}}}"#.utf8))
        try require(vaults.sorted() == ["/Users/dv/Notes", "/Users/dv/Orbit/Obsidian"], "Vaults: \(vaults)")
        try require(P.vault(containing: "/Users/dv/Orbit/Obsidian/Orbit/People/Ron.md", vaults: vaults) == "/Users/dv/Orbit/Obsidian", "Inside")
        try require(P.vault(containing: "/Users/dv/Orbit/Other/x.md", vaults: vaults) == nil, "Outside")
        try require(P.vault(containing: "/Users/dv/NotesOld/x.md", vaults: vaults) == nil, "Prefix is not enough")
        try require(P.obsidianVaults(from: Data("nope".utf8)).isEmpty, "Bad file")

        print("Orbit: all checks passed")
    }
}
