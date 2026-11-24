// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import os

extension Defaults.Keys {
    /// Orbit's master switch. Off means nothing runs: no listeners, no timers,
    /// nothing kept in memory.
    static let enableOrbit = Key<Bool>("enableOrbit", default: false)
    /// Build project pages from terminal commands, AI agents, builds and focus time.
    static let orbitTrackProjects = Key<Bool>("orbitTrackProjects", default: true)
    /// Build people pages from messages and promises.
    static let orbitTrackPeople = Key<Bool>("orbitTrackPeople", default: true)
    /// Write the pages as markdown into an Obsidian vault.
    static let orbitWriteVault = Key<Bool>("orbitWriteVault", default: false)
    /// The vault folder. Empty means ~/Documents/NotchFlow Vault.
    static let orbitVaultPath = Key<String>("orbitVaultPath", default: "")
    /// Also keep a daily note of what happened.
    static let orbitDailyNotes = Key<Bool>("orbitDailyNotes", default: true)
    /// One inbox of everything still open (agents waiting, promises, replies, failing builds, Linear).
    static let orbitLoops = Key<Bool>("orbitLoops", default: true)
    /// Your AI agents as a team board, and handing loops to them.
    static let orbitTeam = Key<Bool>("orbitTeam", default: true)
    /// One-click setups for a kind of work.
    static let orbitScenes = Key<Bool>("orbitScenes", default: true)
    /// A morning brief (a notification and the top of the daily note).
    static let orbitDailyBrief = Key<Bool>("orbitDailyBrief", default: false)
    static let orbitBriefHour = Key<Int>("orbitBriefHour", default: 9)
    /// The day the brief was last given ("2026-11-23").
    static let orbitLastBriefDay = Key<String>("orbitLastBriefDay", default: "")
}

/// Orbit: projects and people that build themselves from what you already do,
/// kept on this Mac and (optionally) written into an Obsidian vault.
///
/// Only the switches are watched while Orbit is off. Turning it on loads the
/// saved state and starts listening; turning it off saves, stops every
/// listener and timer, and drops everything from memory.
@MainActor
final class Orbit: ObservableObject {
    static let shared = Orbit()

    @Published private(set) var state = OrbitState.empty
    /// True while Orbit listens. Other managers check this before calling in,
    /// so a switched-off Orbit costs them one Bool read.
    @Published private(set) var isRunning = false
    @Published private(set) var vaultStatus: String?

    private let log = os.Logger(subsystem: "com.dhruvv620.NotchFlow", category: "Orbit")
    private var switches = Set<AnyCancellable>()
    private var signals = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?
    private var vaultTask: Task<Void, Never>?
    private var dirtyProjects = Set<String>()
    private var dirtyPeople = Set<String>()
    private var agentStates: [String: Bool] = [:]
    private var seenNotifications = Set<String>()
    private var seenPromises = Set<UUID>()
    private var lastBuild: String?
    /// Focus seconds not yet counted as whole minutes, per project.
    private var pendingFocus: [String: TimeInterval] = [:]

    private init() {}

    // MARK: Switches

    func start() {
        guard switches.isEmpty else { return }
        let keys: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.enableOrbit, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitTrackProjects, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitTrackPeople, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitWriteVault, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitDailyNotes, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitLoops, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitLinear, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitTeam, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitScenes, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitDailyBrief, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.orbitBriefHour, options: []).map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(keys).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &switches)
        apply()
    }

    private var tracksProjects: Bool { Defaults[.enableOrbit] && Defaults[.orbitTrackProjects] }
    private var tracksPeople: Bool { Defaults[.enableOrbit] && Defaults[.orbitTrackPeople] }
    var showsLoops: Bool { Defaults[.enableOrbit] && Defaults[.orbitLoops] }

    private func apply() {
        let parts = Defaults[.orbitLinear] || Defaults[.orbitTeam] || Defaults[.orbitScenes] || Defaults[.orbitDailyBrief]
        let shouldRun = tracksProjects || tracksPeople || showsLoops || (Defaults[.enableOrbit] && parts)
        if shouldRun && !isRunning {
            state = Self.load()
            let now = Date()
            state.dismissedLoops = OrbitLoopsPolicy.pruned(state.dismissedLoops, now: now, keepFor: OrbitLoopsPolicy.dismissalMemory)
            state.snoozedLoops = state.snoozedLoops.filter { $0.value > now }
            isRunning = true
            log.info("Orbit on")
        } else if !shouldRun && isRunning {
            shutDown()
            return
        }
        guard isRunning else { return }
        wireSignals()
        OrbitLinear.shared.setActive(true)
        OrbitBriefing.shared.setActive(Defaults[.orbitDailyBrief])
        OrbitJobs.shared.setActive(Defaults[.orbitTeam])
        if Defaults[.orbitWriteVault] { scheduleVaultWrite(all: true) } else { vaultTask?.cancel(); vaultTask = nil; vaultStatus = nil }
    }

    /// Saves, stops every listener and timer, and frees the memory.
    private func shutDown() {
        signals.removeAll()
        OrbitLinear.shared.setActive(false)
        OrbitBriefing.shared.setActive(false)
        OrbitJobs.shared.setActive(false)
        flushFocus()
        let snapshot = state
        saveTask?.cancel(); saveTask = nil
        vaultTask?.cancel(); vaultTask = nil
        Task.detached(priority: .utility) { Self.write(snapshot) }
        state = .empty
        dirtyProjects = []; dirtyPeople = []
        agentStates = [:]; seenNotifications = []; seenPromises = []; lastBuild = nil
        pendingFocus = [:]
        vaultStatus = nil
        isRunning = false
        log.info("Orbit off")
    }

    // MARK: Listening

    private func wireSignals() {
        signals.removeAll()
        if tracksProjects {
            agentStates = Dictionary(AgentHub.shared.sessions.map { ($0.id, $0.isWorking) }, uniquingKeysWith: { a, _ in a })
            AgentHub.shared.$sessions
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.agentsChanged($0) }
                .store(in: &signals)
            lastBuild = BuildWatchManager.shared.announcement?.id
            BuildWatchManager.shared.$announcement
                .compactMap { $0 }
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.buildFinished($0) }
                .store(in: &signals)
        }
        if tracksPeople {
            // Only what arrives from now on; the backlog was seen before.
            seenNotifications = Set(NotificationHub.shared.items.map(\.id))
            NotificationHub.shared.$items
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
                .sink { [weak self] in self?.notificationsChanged($0) }
                .store(in: &signals)
            seenPromises = Set(PromiseKeeper.shared.promises.map(\.id))
            PromiseKeeper.shared.$promises
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.promisesChanged($0) }
                .store(in: &signals)
        }
    }

    private var projectNames: [String] { state.projects.values.map(\.name) }

    private func projectID(mentionedIn text: String) -> String? {
        guard tracksProjects, let name = OrbitPolicy.project(mentionedIn: text, names: projectNames) else { return nil }
        return OrbitPolicy.key(name)
    }

    /// A project for a folder: its root folder's project, or nil outside one.
    private func projectID(forFolder folder: String, fallbackName: String? = nil) -> String? {
        let manager = FileManager.default
        if let root = OrbitPolicy.projectRoot(for: folder, home: NSHomeDirectory(), exists: { manager.fileExists(atPath: $0) }) {
            return OrbitPolicy.upsertProject(name: OrbitPolicy.projectName(root: root), root: root, at: Date(), in: &state)
        }
        guard let fallbackName, !fallbackName.isEmpty else { return nil }
        return OrbitPolicy.upsertProject(name: fallbackName, root: nil, at: Date(), in: &state)
    }

    private func agentsChanged(_ sessions: [AgentSession]) {
        guard tracksProjects else { return }
        for session in sessions {
            let wasWorking = agentStates[session.id] ?? false
            agentStates[session.id] = session.isWorking
            guard wasWorking, !session.isWorking else { continue }
            // Background hand-offs report through OrbitJobs, not here.
            if session.cwd.hasPrefix(OrbitJobs.worktrees.path) { continue }
            let project = projectID(forFolder: session.cwd, fallbackName: session.project)
            let prompt = session.lastPrompt.map { ": \($0)" } ?? ""
            let outcome = session.isWaiting ? "needs you" : "finished"
            let text = "\(session.agent.displayName) \(outcome)\(prompt)"
            let linear = OrbitLinear.shared
            let identifiers = linear.isActive ? OrbitLoopsPolicy.identifiers(in: session.lastPrompt ?? "", teamKeys: linear.teamKeys) : []
            let issueURL = identifiers.first.flatMap { id in linear.issues.first { $0.identifier == id }?.url }
            add(OrbitEvent(date: Date(), kind: .agent, text: text, project: project, url: issueURL))
            // Hand-off: tell the Linear issue the agent worked on.
            if Defaults[.orbitLinearAgentComments], !session.isWaiting {
                for identifier in identifiers {
                    Task { await linear.comment(onIdentifier: identifier, text: "\(text)\n\n_From NotchFlow Orbit_") }
                }
            }
        }
        // Forget sessions that are gone.
        let live = Set(sessions.map(\.id))
        agentStates = agentStates.filter { live.contains($0.key) }
    }

    private func buildFinished(_ run: WatchedRun) {
        guard tracksProjects, run.state != .running, run.id != lastBuild else { return }
        lastBuild = run.id
        let project = projectID(mentionedIn: run.title + " " + run.detail)
        let result = run.state == .success ? "passed" : run.state == .failure ? "failed" : "cancelled"
        add(OrbitEvent(date: Date(), kind: .build, text: "\(run.title) \(result)", project: project, url: run.url?.absoluteString))
    }

    private func notificationsChanged(_ items: [NotchNotification]) {
        guard tracksPeople else { return }
        let fresh = items.filter { !seenNotifications.contains($0.id) }
        seenNotifications = Set(items.map(\.id))
        for item in fresh where OrbitPolicy.isMessagingApp(item.appName) {
            guard let name = OrbitPolicy.personName(fromTitle: item.title) else { continue }
            // Only people you pinned get a page; others just show in Loops.
            let person = OrbitPolicy.pinnedPerson(named: name, in: state)
            let project = projectID(mentionedIn: item.body)
            guard person != nil || project != nil else { continue }
            if let person, var entry = state.people[person] {
                entry.lastApp = item.appName
                state.people[person] = entry
            }
            // Message text stays out of the log unless it ties to a project.
            let text = project != nil ? "\(name): \(item.body)" : "Message on \(item.appName)"
            add(OrbitEvent(date: item.date, kind: .message, text: text, project: project, person: person))
        }
    }

    private func promisesChanged(_ promises: [TrackedPromise]) {
        guard tracksPeople else { return }
        for promise in promises where !seenPromises.contains(promise.id) {
            seenPromises.insert(promise.id)
            let person = OrbitPolicy.personName(fromTitle: promise.person).flatMap { OrbitPolicy.pinnedPerson(named: $0, in: state) }
            let project = projectID(mentionedIn: promise.title + " " + promise.quote)
            guard person != nil || project != nil else { continue }
            add(OrbitEvent(date: promise.created, kind: .promise, text: promise.title, project: project, person: person))
        }
    }

    /// From the Terminal tab: a command finished in `folder`.
    func commandFinished(_ command: String, duration: TimeInterval, folder: String?) {
        guard isRunning, tracksProjects, OrbitPolicy.isNoteworthy(command: command, duration: duration),
              let folder, let project = projectID(forFolder: folder) else { return }
        add(OrbitEvent(date: Date(), kind: .command, text: OrbitPolicy.describe(command: command, duration: duration), project: project))
    }

    /// From time tracking: `seconds` spent on a project named in a window title.
    func focused(onProjectNamed name: String, seconds: TimeInterval) {
        guard isRunning, tracksProjects, seconds > 0 else { return }
        let id = OrbitPolicy.key(name)
        // Only projects Orbit already knows; window titles are noisy.
        guard state.projects[id] != nil else { return }
        pendingFocus[id, default: 0] += seconds
        if pendingFocus[id, default: 0] >= 60 { flushFocus() }
    }

    private func flushFocus() {
        let day = OrbitPolicy.dayKey(Date())
        for (id, seconds) in pendingFocus where seconds >= 60 {
            OrbitPolicy.addFocus(minutes: Int(seconds / 60), project: id, day: day, in: &state)
            pendingFocus[id] = seconds.truncatingRemainder(dividingBy: 60)
            dirtyProjects.insert(id)
        }
        scheduleSave()
    }

    private func add(_ event: OrbitEvent) {
        OrbitPolicy.record(event, in: &state)
        if let project = event.project { dirtyProjects.insert(project) }
        if let person = event.person { dirtyPeople.insert(person) }
        scheduleSave()
        if Defaults[.orbitWriteVault] { scheduleVaultWrite(all: false) }
    }

    // MARK: Linear

    func linearIssueMoved(_ issue: LinearIssue, from: String) {
        guard isRunning, tracksProjects else { return }
        let project = OrbitLoopsPolicy.project(for: issue, projects: Array(state.projects.values))
        add(OrbitEvent(date: Date(), kind: .note, text: "\(issue.identifier) \(issue.title): \(from) → \(issue.stateName)",
                       project: project, url: issue.url))
    }

    func linearIssueCreated(identifier: String, title: String, url: String, project: String?) {
        guard isRunning else { return }
        add(OrbitEvent(date: Date(), kind: .note, text: "Created \(identifier) \(title)", project: project, url: url))
    }

    // MARK: Loops

    /// Everything still open, from what the other features already hold in
    /// memory. Worked out when the tab asks, so it costs nothing in between.
    func loops(now: Date = Date()) -> [OrbitLoop] {
        guard isRunning, showsLoops else { return [] }
        var all: [OrbitLoop] = []
        for job in OrbitJobs.shared.jobs where job.state == .review {
            all.append(OrbitLoop(id: "review:\(job.id.uuidString)", kind: .review, title: "Review: \(job.title)",
                                 detail: job.changes.summary, date: job.finished ?? job.started, project: job.project, url: job.url))
        }
        for session in AgentHub.shared.sessions where session.isWaiting {
            var detail = session.project
            if let prompt = session.lastPrompt { detail += " · " + OrbitPolicy.clip(prompt, to: 80) }
            all.append(OrbitLoop(id: "agent:\(session.id)", kind: .agent, title: "\(session.agent.displayName) needs you",
                                 detail: detail, date: session.updatedAt, project: OrbitPolicy.key(session.project)))
        }
        for promise in PromiseKeeper.shared.promises where promise.status == .open {
            let mine = promise.kind == .mine
            all.append(OrbitLoop(id: "promise:\(promise.id.uuidString)", kind: mine ? .promise : .theirPromise,
                                 title: mine ? "You promised \(promise.person): \(promise.title)" : "\(promise.person) promised: \(promise.title)",
                                 detail: "Due " + promise.due.formatted(date: .abbreviated, time: promise.hasExplicitTime ? .shortened : .omitted),
                                 date: promise.created, due: promise.due, person: OrbitPolicy.key(promise.person),
                                 personName: OrbitPolicy.personName(fromTitle: promise.person)))
        }
        for run in BuildWatchManager.shared.runs where run.state == .failure {
            all.append(OrbitLoop(id: "build:\(run.id)", kind: .build, title: "\(run.title) failed", detail: run.detail,
                                 date: run.updatedAt, project: projectID(mentionedIn: run.title), url: run.url?.absoluteString))
        }
        let messages = NotificationHub.shared.items
            .filter { OrbitPolicy.isMessagingApp($0.appName) }
            .map { OrbitLoopsPolicy.Message(app: $0.appName, sender: $0.title, text: $0.body, date: $0.date) }
        all += OrbitLoopsPolicy.messageLoops(messages)
        let projects = Array(state.projects.values)
        all += OrbitLinear.shared.issues.map { OrbitLoopsPolicy.loop(for: $0, project: OrbitLoopsPolicy.project(for: $0, projects: projects)) }
        return OrbitLoopsPolicy.visible(all, dismissed: state.dismissedLoops, snoozed: state.snoozedLoops, now: now)
    }

    /// Opens what the loop is about.
    func open(_ loop: OrbitLoop) {
        switch loop.kind {
        case .agent:
            let id = String(loop.id.dropFirst("agent:".count))
            if let session = AgentHub.shared.sessions.first(where: { $0.id == id }), session.appBundleID != nil {
                AgentHub.shared.openWindow(bundleID: session.appBundleID)
            } else {
                DynamicIslandViewCoordinator.shared.currentView = .agents
            }
        case .message:
            let person = loop.person
            if let item = NotificationHub.shared.items
                .filter({ OrbitPolicy.isMessagingApp($0.appName) && OrbitPolicy.personName(fromTitle: $0.title).map(OrbitPolicy.key) == person })
                .max(by: { $0.date < $1.date }) {
                NotificationHub.shared.open(item)
            }
        case .promise, .theirPromise:
            PromiseKeeper.shared.showListRequested = true
            DynamicIslandViewCoordinator.shared.currentView = .reminders
        case .build, .linear:
            if let link = loop.url, let url = URL(string: link) { NSWorkspace.shared.open(url) }
        case .review:
            requestedTabMode = "team"
        }
    }

    /// Closes the loop: promises are marked done, Linear issues moved to Done,
    /// the rest hidden until something new comes in.
    func done(_ loop: OrbitLoop) {
        switch loop.kind {
        case .promise, .theirPromise:
            if let id = UUID(uuidString: String(loop.id.dropFirst("promise:".count))) { PromiseKeeper.shared.markDone(id) }
        case .linear:
            if let issue = loop.issueID { Task { await OrbitLinear.shared.move(issueID: issue, toType: "completed") } }
        default:
            state.dismissedLoops[loop.id] = Date()
            scheduleSave()
        }
    }

    func snooze(_ loop: OrbitLoop, hours: Double) {
        if loop.kind == .promise || loop.kind == .theirPromise,
           let id = UUID(uuidString: String(loop.id.dropFirst("promise:".count))) {
            PromiseKeeper.shared.snooze(id, by: hours * 3600)
            return
        }
        state.snoozedLoops[loop.id] = Date().addingTimeInterval(hours * 3600)
        scheduleSave()
    }

    /// Makes a Linear issue from a loop or a timeline entry.
    func sendToLinear(title: String, detail: String, project: String?) {
        Task { await OrbitLinear.shared.createIssue(title: title, description: detail + "\n\n_From NotchFlow Orbit_", project: project) }
    }

    // MARK: Team (agents)

    var showsTeam: Bool { Defaults[.enableOrbit] && Defaults[.orbitTeam] }

    /// The folder to start an agent in for a project.
    func folder(forProject id: String?) -> String? {
        guard let id else { return nil }
        if let root = state.projects[id]?.root { return root }
        // Agent sessions name projects by folder name.
        return AgentHub.shared.recentProjects.first { OrbitPolicy.key(($0 as NSString).lastPathComponent) == id }
    }

    /// Gives a loop to an AI agent: it starts in the loop's project folder
    /// with the loop as its task, and the loop is marked handed off.
    func handOff(_ loop: OrbitLoop, to agent: AgentHookPolicy.LaunchAgent, folder: String) {
        guard isRunning, showsTeam else { return }
        let project = loop.project ?? projectID(forFolder: folder)
        // The context pack: what the agent would otherwise have to ask you.
        let description = loop.issueID.flatMap { id in OrbitLinear.shared.issues.first { $0.id == id }?.description }
        let failedBuild = BuildWatchManager.shared.runs.first { run in
            run.state == .failure && (loop.kind == .build ? "build:\(run.id)" == loop.id
                                      : project != nil && projectID(mentionedIn: run.title + " " + run.detail) == project)
        }
        let prompt = OrbitTeamPolicy.handoffPrompt(
            title: loop.title, detail: loop.detail, url: loop.url, description: description,
            buildFailure: failedBuild.map { "\($0.title) (\($0.detail))" + ($0.url.map { " \($0.absoluteString)" } ?? "") },
            history: project.map { OrbitTeamPolicy.history(for: $0, in: state) } ?? [])
        // Claude Code and Codex work out of sight in their own copy of the
        // project; the others open in a terminal.
        let background = Defaults[.orbitBackgroundHandoffs] && OrbitJobs.shared.start(
            agent: agent, title: loop.title, prompt: prompt, folder: folder, project: project,
            loopID: loop.id, issueID: loop.issueID, url: loop.url)
        if !background { AgentHub.shared.startTask(agent: agent, prompt: prompt, directory: folder) }
        add(OrbitEvent(date: Date(), kind: .agent, text: "Handed to \(agent.title): \(loop.title)", project: project, url: loop.url))
        if loop.kind != .linear && loop.kind != .promise && loop.kind != .theirPromise {
            state.dismissedLoops[loop.id] = Date()
        }
        if loop.kind == .linear, let issue = loop.issueID {
            Task { await OrbitLinear.shared.move(issueID: issue, toType: "started") }
        }
    }

    /// A background job came back.
    func jobFinished(_ job: OrbitJob, agentName: String) {
        guard isRunning else { return }
        let outcome = job.state == .review ? "finished (\(job.changes.summary))" : "stopped: \(job.error ?? "error")"
        add(OrbitEvent(date: Date(), kind: .agent, text: "\(agentName) \(outcome): \(job.title)", project: job.project, url: job.url))
        if job.state == .review, let issue = job.issueID, Defaults[.orbitLinearAgentComments] {
            let text = "\(agentName) finished this from NotchFlow Orbit (\(job.changes.summary)).\n\n\(job.summary)"
            Task { await OrbitLinear.shared.comment(issueID: issue, text: text) }
        }
    }

    /// You decided what to do with a job's changes.
    func jobClosed(_ job: OrbitJob, outcome: String) {
        guard isRunning else { return }
        add(OrbitEvent(date: Date(), kind: .agent, text: "\(outcome): \(job.title)", project: job.project, url: job.url))
    }

    /// Set to show a view in the Orbit tab (a review loop opens Team).
    @Published var requestedTabMode: String?

    // MARK: Scenes

    var showsScenes: Bool { Defaults[.enableOrbit] && Defaults[.orbitScenes] }

    func saveScene(_ scene: OrbitScene) {
        guard isRunning else { return }
        if let index = state.scenes.firstIndex(where: { $0.id == scene.id }) {
            state.scenes[index] = scene
        } else {
            state.scenes.append(scene)
        }
        scheduleSave()
    }

    func deleteScene(_ id: UUID) {
        guard isRunning else { return }
        state.scenes.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Runs each step the scene has.
    func run(_ scene: OrbitScene) {
        guard isRunning, showsScenes else { return }
        if let id = scene.workspace, let workspace = WorkspaceManager.shared.workspaces.first(where: { $0.id == id }) {
            WorkspaceManager.shared.open(workspace)
        }
        if scene.quietMinutes > 0 { FocusQuiet.shared.startManual(minutes: scene.quietMinutes) }
        let directory = folder(forProject: scene.project)
        if scene.openTerminal, let directory, Defaults[.enableTerminalFeature] {
            TerminalManager.shared.newSession(in: directory)
            DynamicIslandViewCoordinator.shared.currentView = .terminal
        }
        let task = scene.agentTask.trimmingCharacters(in: .whitespacesAndNewlines)
        if !task.isEmpty, let directory {
            let agent = AgentHookPolicy.LaunchAgent(rawValue: Defaults[.agentLaunchAgent]) ?? .claude
            AgentHub.shared.startTask(agent: agent, prompt: task, directory: directory)
        }
        add(OrbitEvent(date: Date(), kind: .note, text: "Started scene \(scene.name)", project: scene.project))
    }

    // MARK: Daily brief

    /// Builds the brief from now's state, keeps it for the daily note, and returns it.
    @discardableResult
    func makeBrief() -> OrbitBrief? {
        guard isRunning else { return nil }
        let meetings = CalendarManager.shared.events.map {
            OrbitTeamPolicy.Meeting(title: $0.title, start: $0.start, allDay: $0.isAllDay)
        }
        let brief = OrbitTeamPolicy.brief(state: state, loops: loops(), meetings: meetings, now: Date())
        state.lastBrief = brief
        scheduleSave()
        if Defaults[.orbitWriteVault] { scheduleVaultWrite(all: false) }
        return brief
    }

    // MARK: People

    func isPinned(_ name: String) -> Bool {
        OrbitPolicy.personName(fromTitle: name).flatMap { OrbitPolicy.pinnedPerson(named: $0, in: state) } != nil
    }

    /// Gives someone a People page; their messages and promises are kept from now on.
    func pin(_ name: String, app: String? = nil) {
        guard isRunning, let clean = OrbitPolicy.personName(fromTitle: name) else { return }
        let id = OrbitPolicy.pinPerson(name: clean, app: app, at: Date(), in: &state)
        dirtyPeople.insert(id)
        scheduleSave()
        if Defaults[.orbitWriteVault] { scheduleVaultWrite(all: false) }
    }

    /// Removes someone's page (their note in the vault stays).
    func unpin(_ id: String) {
        guard isRunning else { return }
        OrbitPolicy.unpinPerson(id, in: &state)
        scheduleSave()
    }

    // MARK: Editing from the UI

    func togglePin(_ id: String) {
        guard isRunning else { return }
        state.projects[id]?.pinned.toggle()
        scheduleSave()
    }

    func addNote(_ text: String, project: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRunning, !trimmed.isEmpty else { return }
        add(OrbitEvent(date: Date(), kind: .note, text: trimmed, project: project))
    }

    func forget(project id: String) {
        guard isRunning else { return }
        state.projects[id] = nil
        state.events.removeAll { $0.project == id }
        for key in state.people.keys { state.people[key]?.projects[id] = nil }
        scheduleSave()
    }

    /// Deletes everything Orbit kept (the vault's notes stay).
    func forgetEverything() {
        state = .empty
        dirtyProjects = []; dirtyPeople = []
        pendingFocus = [:]
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: Self.storeURL) }
    }

    // MARK: Saving

    nonisolated static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NotchFlow/Orbit/orbit.json")
    }

    private static func load() -> OrbitState {
        guard let data = try? Data(contentsOf: storeURL),
              let state = try? JSONDecoder().decode(OrbitState.self, from: data) else { return .empty }
        return OrbitPolicy.migrated(state)
    }

    nonisolated private static func write(_ state: OrbitState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            let snapshot = self.state
            await Task.detached(priority: .utility) { Self.write(snapshot) }.value
        }
    }

    // MARK: Obsidian vault

    var vaultURL: URL {
        let path = Defaults[.orbitVaultPath].trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/NotchFlow Vault", isDirectory: true)
    }

    /// Where Orbit's own notes go inside the vault.
    var orbitFolder: URL { vaultURL.appendingPathComponent("Orbit", isDirectory: true) }

    func noteURL(forProject project: OrbitProject) -> URL {
        orbitFolder.appendingPathComponent("Projects/\(OrbitPolicy.fileName(project.name)).md")
    }

    func noteURL(forPerson person: OrbitPerson) -> URL {
        orbitFolder.appendingPathComponent("People/\(OrbitPolicy.fileName(person.name)).md")
    }

    func writeVaultNow() { scheduleVaultWrite(all: true, delay: 0) }

    private func scheduleVaultWrite(all: Bool, delay: Double = 20) {
        guard isRunning, Defaults[.orbitWriteVault] else { return }
        if all {
            dirtyProjects.formUnion(state.projects.keys)
            dirtyPeople.formUnion(state.people.keys)
        }
        vaultTask?.cancel()
        vaultTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            await self.writeVault()
        }
    }

    private struct NoteFile: Sendable {
        let url: URL
        let header: String
        let body: String
    }

    private func writeVault() async {
        guard isRunning, Defaults[.orbitWriteVault] else { return }
        flushFocus()
        var files: [NoteFile] = []
        for id in dirtyProjects {
            guard let project = state.projects[id] else { continue }
            files.append(NoteFile(url: noteURL(forProject: project), header: OrbitPolicy.projectNoteHeader(project),
                                  body: OrbitPolicy.projectNote(project, state: state)))
        }
        for id in dirtyPeople {
            guard let person = state.people[id] else { continue }
            files.append(NoteFile(url: noteURL(forPerson: person), header: OrbitPolicy.personNoteHeader(person),
                                  body: OrbitPolicy.personNote(person, state: state)))
        }
        if Defaults[.orbitDailyNotes] {
            let day = OrbitPolicy.dayKey(Date())
            files.append(NoteFile(url: orbitFolder.appendingPathComponent("Daily/\(day).md"),
                                  header: OrbitPolicy.dailyNoteHeader(day: day), body: OrbitPolicy.dailyNote(day: day, state: state)))
        }
        dirtyProjects = []; dirtyPeople = []
        let vault = vaultURL
        let failed = await Task.detached(priority: .utility) { () -> String? in
            let manager = FileManager.default
            do {
                // A new vault: make it one Obsidian recognizes.
                if !manager.fileExists(atPath: vault.path) {
                    try manager.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
                }
                for file in files {
                    try manager.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let existing = try? String(contentsOf: file.url, encoding: .utf8)
                    let merged = OrbitPolicy.merge(existing: existing, managed: file.body, header: file.header)
                    if merged != existing { try merged.write(to: file.url, atomically: true, encoding: .utf8) }
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        guard isRunning else { return }
        let time = Date().formatted(date: .omitted, time: .shortened)
        vaultStatus = failed.map { "Couldn't write the vault: \($0)" } ?? "Vault updated at \(time)"
    }

    var hasObsidian: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "md.obsidian") != nil }

    /// The vaults Obsidian has opened (it only opens links inside one of them).
    private var obsidianVaults: [String] {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return OrbitPolicy.obsidianVaults(from: data)
    }

    /// Whether Obsidian has this vault (or a folder around it) open as a vault.
    var obsidianKnowsVault: Bool {
        OrbitPolicy.vault(containing: orbitFolder.path, vaults: obsidianVaults) != nil
    }

    /// Opens a note (or the vault) in Obsidian. If Obsidian hasn't opened the
    /// vault yet, shows the folder in Finder and says how to add it.
    func openInObsidian(_ url: URL?) {
        let target = url ?? orbitFolder
        let manager = FileManager.default
        guard manager.fileExists(atPath: target.path) else {
            vaultStatus = "Nothing written yet. Press Write Now in Settings › Orbit."
            NSWorkspace.shared.open(vaultURL.deletingLastPathComponent())
            return
        }
        if hasObsidian, OrbitPolicy.vault(containing: target.path, vaults: obsidianVaults) != nil,
           let link = OrbitPolicy.obsidianURL(forFile: target.path) {
            NSWorkspace.shared.open(link)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
        if hasObsidian {
            vaultStatus = "Obsidian doesn't know this vault yet: in Obsidian, choose Open folder as vault and pick \(vaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))."
        }
    }
}
