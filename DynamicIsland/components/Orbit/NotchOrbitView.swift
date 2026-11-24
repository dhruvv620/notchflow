// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI

/// The Orbit tab: projects and people that built themselves from your day,
/// with each one's timeline and a link to its note in the Obsidian vault.
struct NotchOrbitView: View {
    @ObservedObject private var orbit = Orbit.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.orbitTrackProjects) private var trackProjects
    @Default(.orbitTrackPeople) private var trackPeople
    @Default(.orbitWriteVault) private var writeVault
    @Default(.orbitLoops) private var showLoops
    @Default(.orbitLinear) private var linearOn
    @ObservedObject private var linear = OrbitLinear.shared
    // Loops are worked out from other features' live data; these keep the
    // list fresh while the tab is open.
    @ObservedObject private var agents = AgentHub.shared
    @ObservedObject private var promises = PromiseKeeper.shared
    @ObservedObject private var hub = NotificationHub.shared
    @Default(.orbitTeam) private var showTeam
    @Default(.orbitScenes) private var showScenes
    @Default(.orbitDailyBrief) private var briefOn

    enum Mode: String, CaseIterable {
        case today, loops, team, projects, people
        var title: String { rawValue.capitalized }
    }
    @State private var mode: Mode = .loops
    @State private var selectedProject: String?
    @State private var selectedPerson: String?
    @State private var draft = ""
    @State private var interactionToken = UUID()
    @FocusState private var noteFocused: Bool
    @FocusState private var followUpFocused: Bool
    @ObservedObject private var jobsModel = OrbitJobs.shared
    @State private var followUps: [UUID: String] = [:]
    @State private var expandedJob: UUID?

    private var projects: [OrbitProject] { OrbitPolicy.activeProjects(orbit.state, now: Date()) }
    private var people: [OrbitPerson] {
        orbit.state.people.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            header
            if !orbit.isRunning {
                NotchEmptyState(symbol: "circle.dashed", title: "Orbit is off",
                                detail: "Turn on Loops, Projects or People in Settings › Orbit.") {
                    NotchPillButton(title: "Open Settings", symbol: "gearshape") { SettingsWindowController.shared.showWindow() }
                }
            } else if mode == .today {
                todayView
            } else if mode == .team {
                teamView
            } else if mode == .loops {
                loopsView
            } else if mode == .projects {
                if projects.isEmpty {
                    NotchEmptyState(symbol: "folder.badge.plus", title: "No projects yet",
                                    detail: "Run a command in the Terminal tab or let an AI agent work in a project folder. Orbit makes the page itself.")
                } else {
                    split(list: projectList, detail: projectDetail)
                }
            } else {
                if people.isEmpty {
                    NotchEmptyState(symbol: "pin", title: "No pinned people",
                                    detail: "Only people you pin get a page. In Loops, right-click a message or promise and choose Pin to People.")
                } else {
                    split(list: peopleList, detail: personDetail)
                }
            }
        }
        .notchTabPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            fixMode()
            if linear.isActive { Task { await linear.refresh() } }
        }
        .onChange(of: trackProjects) { _, _ in fixMode() }
        .onChange(of: trackPeople) { _, _ in fixMode() }
        .onChange(of: showLoops) { _, _ in fixMode() }
        .onChange(of: showTeam) { _, _ in fixMode() }
        .onChange(of: showScenes) { _, _ in fixMode() }
        .onChange(of: briefOn) { _, _ in fixMode() }
        .onChange(of: noteFocused) { _, _ in
            vm.setAutoCloseSuppression(noteFocused || followUpFocused, token: interactionToken)
        }
        .onChange(of: followUpFocused) { _, _ in
            vm.setAutoCloseSuppression(noteFocused || followUpFocused, token: interactionToken)
        }
        .onChange(of: orbit.requestedTabMode) { _, requested in
            if let requested, let target = Mode(rawValue: requested), modes.contains(target) { mode = target }
            orbit.requestedTabMode = nil
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: interactionToken) }
    }

    private var modes: [Mode] {
        Mode.allCases.filter { mode in
            switch mode {
            case .today: return briefOn || showScenes
            case .loops: return showLoops
            case .team: return showTeam
            case .projects: return trackProjects
            case .people: return trackPeople
            }
        }
    }

    private func fixMode() {
        if !modes.contains(mode), let first = modes.first { mode = first }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Text("Orbit").font(NotchTokens.Typography.title)
            if modes.count > 1 {
                Picker("", selection: $mode) {
                    ForEach(modes, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Spacer(minLength: 0)
            if writeVault, let status = orbit.vaultStatus {
                Text(status).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if writeVault {
                NotchIconButton(symbol: "book.closed", help: "Open the vault in Obsidian") { orbit.openInObsidian(nil) }
            }
        }
    }

    private func split<L: View, D: View>(list: L, detail: D) -> some View {
        HStack(alignment: .top, spacing: NotchTokens.Spacing.m) {
            ScrollView(.vertical, showsIndicators: false) { list }
                .frame(width: 170)
            Divider().opacity(0.3)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Loops

    @ViewBuilder private var loopsView: some View {
        let loops = Orbit.shared.loops()
        VStack(alignment: .leading, spacing: 4) {
            if linearOn, let error = linear.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(NotchTokens.Typography.caption).foregroundStyle(.orange).lineLimit(1)
            }
            if loops.isEmpty {
                NotchEmptyState(symbol: "checkmark.circle", title: "Nothing open",
                                detail: "Agents waiting on you, promises, unanswered messages, failing builds and your Linear issues show up here.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(loops) { loop in loopRow(loop) }
                    }
                }
            }
        }
    }

    private func loopRow(_ loop: OrbitLoop) -> some View {
        HStack(spacing: 8) {
            Image(systemName: loop.kind.symbol)
                .font(.system(size: 11))
                .foregroundStyle(loop.kind == .agent || loop.kind == .build ? Color.orange : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(loop.title).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                if !loop.detail.isEmpty {
                    Text(loop.detail).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let due = loop.due, due < Date() {
                NotchBadge(text: "Overdue", tint: .red)
            } else {
                Text(relative(loop.date)).font(NotchTokens.Typography.caption).foregroundStyle(.tertiary)
            }
            if showTeam, loop.kind == .build || loop.kind == .linear,
               let folder = orbit.folder(forProject: loop.project) ?? agents.recentProjects.first {
                let agent = AgentHookPolicy.LaunchAgent(rawValue: Defaults[.agentLaunchAgent]) ?? .claude
                NotchIconButton(symbol: "sparkles",
                                help: "Let \(agent.title) do it in \((folder as NSString).lastPathComponent)", size: 20) {
                    orbit.handOff(loop, to: agent, folder: folder)
                    mode = .team
                }
            }
            if loop.kind == .linear, let issue = loop.issueID {
                NotchIconButton(symbol: "play", help: "Start (move to In Progress)", size: 20) {
                    Task { await linear.move(issueID: issue, toType: "started") }
                }
            }
            Menu {
                Button("In an Hour") { Orbit.shared.snooze(loop, hours: 1) }
                Button("Tomorrow") { Orbit.shared.snooze(loop, hours: 20) }
                Button("Next Week") { Orbit.shared.snooze(loop, hours: 24 * 7) }
            } label: {
                Image(systemName: "clock").font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Snooze")
            NotchIconButton(symbol: "checkmark", help: loop.kind == .linear ? "Done (moves the issue to Done)" : "Done", size: 20) {
                Orbit.shared.done(loop)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous).fill(Color.white.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { Orbit.shared.open(loop) }
        .contextMenu {
            Button("Open") { Orbit.shared.open(loop) }
            if trackPeople, let name = loop.personName {
                if orbit.isPinned(name) {
                    Button("Unpin \(name)") { orbit.unpin(OrbitPolicy.key(name)) }
                } else {
                    Button("Pin \(name) to People") { orbit.pin(name, app: loop.kind == .message ? loop.detail.components(separatedBy: ":").first : nil) }
                }
            }
            if showTeam, let folder = orbit.folder(forProject: loop.project) ?? agents.recentProjects.first {
                Menu("Hand Off in \((folder as NSString).lastPathComponent)") {
                    ForEach(AgentHookPolicy.LaunchAgent.allCases, id: \.self) { agent in
                        Button(agent.title) { orbit.handOff(loop, to: agent, folder: folder) }
                    }
                }
            }
            if linear.isActive && loop.kind != .linear {
                Button("Create Linear Issue") {
                    Orbit.shared.sendToLinear(title: loop.title, detail: loop.detail, project: loop.project)
                }
            }
        }
    }

    // MARK: Today

    @ViewBuilder private var todayView: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            if briefOn {
                briefCard
            }
            if showScenes {
                scenesRow
            }
        }
    }

    private var briefCard: some View {
        NotchCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sun.max").foregroundStyle(.yellow)
                    Text(currentBrief?.headline ?? "Your brief").font(NotchTokens.Typography.headline)
                    Spacer(minLength: 0)
                    NotchIconButton(symbol: "arrow.clockwise", help: "Make the brief again", size: 20) { orbit.makeBrief() }
                }
                if let brief = currentBrief {
                    ForEach(brief.lines, id: \.self) { line in
                        Text("• " + line).font(NotchTokens.Typography.body).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text("Comes each morning at the hour set in Settings › Orbit. Refresh to make one now.")
                        .font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentBrief: OrbitBrief? {
        guard let brief = orbit.state.lastBrief, brief.day == OrbitPolicy.dayKey(Date()) else { return nil }
        return brief
    }

    private var scenesRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Scenes").font(NotchTokens.Typography.captionEmphasis).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let top = projects.first, !orbit.state.scenes.contains(where: { $0.project == top.id }) {
                    NotchPillButton(title: "Scene for \(top.name)", symbol: "plus") {
                        orbit.saveScene(OrbitTeamPolicy.starterScene(for: top))
                    }
                }
                NotchIconButton(symbol: "slider.horizontal.3", help: "Edit scenes in Settings", size: 20) {
                    SettingsWindowController.shared.showWindow()
                }
            }
            if orbit.state.scenes.isEmpty {
                Text("A scene sets you up in one click: a workspace, quiet time, a terminal in the project and an agent on a task.")
                    .font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NotchTokens.Spacing.s) {
                        ForEach(orbit.state.scenes) { scene in sceneCard(scene) }
                    }
                }
            }
        }
    }

    private func sceneCard(_ scene: OrbitScene) -> some View {
        let project = scene.project.flatMap { orbit.state.projects[$0] }
        let workspace = scene.workspace.flatMap { id in WorkspaceManager.shared.workspaces.first { $0.id == id } }
        let steps = OrbitTeamPolicy.steps(of: scene, projectName: project?.name, workspaceName: workspace?.name)
        return Button { orbit.run(scene) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: scene.symbol).font(.system(size: 11))
                    Text(scene.name).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                    Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Text(steps.joined(separator: " · ")).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(width: 180, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Run this scene")
        .contextMenu {
            Button("Delete Scene", role: .destructive) { orbit.deleteScene(scene.id) }
        }
    }

    // MARK: Team

    @ViewBuilder private var teamView: some View {
        // Background hand-off sessions show as jobs, not twice.
        let members = agents.sessions
            .filter { !$0.cwd.hasPrefix(OrbitJobs.worktrees.path) }
            .sorted { a, b in
                (a.isWaiting ? 0 : a.isWorking ? 1 : 2, b.updatedAt) < (b.isWaiting ? 0 : b.isWorking ? 1 : 2, a.updatedAt)
            }
        let jobs = jobsModel.visibleJobs
        if members.isEmpty && jobs.isEmpty {
            NotchEmptyState(symbol: "person.3", title: "No agents at work",
                            detail: "Right-click anything in Loops and choose Hand Off: the agent works out of sight in its own copy of the project and comes back with changes to review.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if !jobs.isEmpty {
                        HStack {
                            Text("Hand-offs").font(NotchTokens.Typography.captionEmphasis).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if jobs.contains(where: { !$0.state.isOpen }) {
                                Button("Clear finished") { jobsModel.clearFinished() }
                                    .buttonStyle(.plain).font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(jobs) { job in jobCard(job) }
                    }
                    if !members.isEmpty {
                        if !jobs.isEmpty {
                            Text("Sessions").font(NotchTokens.Typography.captionEmphasis).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(members) { session in memberCard(session) }
                        }
                    }
                }
            }
        }
    }

    private func jobCard(_ job: OrbitJob) -> some View {
        let agentName = AgentHookPolicy.LaunchAgent(rawValue: job.agent)?.title ?? job.agent
        let tint: Color = {
            switch job.state {
            case .running: return .blue
            case .review: return .green
            case .failed: return .orange
            default: return .secondary
            }
        }()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if job.state == .running {
                    ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                } else {
                    Image(systemName: job.state == .review ? "checkmark.seal.fill" : job.state == .failed ? "exclamationmark.triangle.fill" : "checkmark")
                        .font(.system(size: 11)).foregroundStyle(tint)
                }
                Text(job.title).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                Spacer(minLength: 4)
                Text(jobStatus(job, agentName: agentName)).font(NotchTokens.Typography.caption).foregroundStyle(tint).lineLimit(1)
            }
            if job.state == .running {
                HStack {
                    Text("\(agentName) is working in its own copy of \(job.project ?? (job.folder as NSString).lastPathComponent). Your files aren't touched.")
                        .font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    NotchPillButton(title: "Stop", symbol: "stop.fill") { jobsModel.stop(job) }
                }
            }
            if job.state == .review || job.state == .failed {
                if !job.summary.isEmpty {
                    Text(job.summary).font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                        .lineLimit(expandedJob == job.id ? 12 : 2)
                        .onTapGesture { expandedJob = expandedJob == job.id ? nil : job.id }
                }
                if let error = job.error {
                    Text(error).font(NotchTokens.Typography.caption).foregroundStyle(.orange).lineLimit(2)
                }
                if !job.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(job.changes.files.prefix(expandedJob == job.id ? 30 : 3), id: \.path) { file in
                            HStack(spacing: 6) {
                                Text(file.path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 4)
                                Text("+\(file.added)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.green)
                                Text("−\(file.removed)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.red)
                            }
                        }
                        if job.changes.files.count > 3 && expandedJob != job.id {
                            Button("\(job.changes.files.count - 3) more files") { expandedJob = job.id }
                                .buttonStyle(.plain).font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 6) {
                    if job.state == .review {
                        NotchPillButton(title: "See changes", symbol: "doc.text.magnifyingglass") { jobsModel.seeChanges(job) }
                        if job.branch != nil && !job.changes.isEmpty {
                            NotchPillButton(title: "Apply", symbol: "square.and.arrow.down") { Task { await jobsModel.apply(job, commit: false) } }
                            NotchPillButton(title: "Commit", symbol: "checkmark.circle", prominent: true) { Task { await jobsModel.apply(job, commit: true) } }
                        } else {
                            NotchPillButton(title: "Done", symbol: "checkmark", prominent: true) { Task { await jobsModel.apply(job, commit: false) } }
                        }
                    }
                    Spacer(minLength: 0)
                    NotchPillButton(title: "Throw away", symbol: "trash") { Task { await jobsModel.discard(job) } }
                }
                if job.sessionID != nil {
                    NotchComposeField(placeholder: "Keep going: tell \(agentName) what else to do",
                                      text: Binding(get: { followUps[job.id] ?? "" }, set: { followUps[job.id] = $0 }),
                                      onSend: {
                                          jobsModel.keepGoing(job, message: followUps[job.id] ?? "")
                                          followUps[job.id] = nil
                                      },
                                      isFocused: $followUpFocused)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous)
            .fill(Color.white.opacity(job.state.isOpen ? 0.07 : 0.03)))
        .contextMenu {
            Button("Show Its Folder") { jobsModel.openWorkFolder(job) }
            if let link = job.url, let url = URL(string: link) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func jobStatus(_ job: OrbitJob, agentName: String) -> String {
        switch job.state {
        case .running: return OrbitTeamPolicy.status(working: true, waiting: false, since: job.started, now: Date())
        case .review: return job.changes.summary
        case .failed: return "Stopped"
        case .applied: return "Applied"
        case .committed: return "Committed"
        case .discarded: return "Thrown away"
        }
    }

    private func memberCard(_ session: AgentSession) -> some View {
        let status = OrbitTeamPolicy.status(working: session.isWorking, waiting: session.isWaiting,
                                            since: session.turnStartedAt ?? session.updatedAt, now: Date())
        let tint: Color = session.isWaiting ? .orange : session.isWorking ? .green : .secondary
        return Button {
            if session.appBundleID != nil {
                agents.openWindow(bundleID: session.appBundleID)
            } else {
                DynamicIslandViewCoordinator.shared.currentView = .agents
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(session.agent.displayName).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(session.project).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(status).font(NotchTokens.Typography.caption).foregroundStyle(tint)
                if let prompt = session.lastPrompt {
                    Text(prompt).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Projects

    private var currentProject: OrbitProject? {
        let list = projects
        return list.first { $0.id == selectedProject } ?? list.first
    }

    private var projectList: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(projects) { project in
                listRow(title: project.name, detail: relative(project.lastActive),
                        symbol: project.pinned ? "pin.fill" : "folder",
                        selected: project.id == currentProject?.id) {
                    selectedProject = project.id
                }
                .contextMenu {
                    Button(project.pinned ? "Unpin" : "Pin") { orbit.togglePin(project.id) }
                    if let root = project.root {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)]) }
                    }
                    Divider()
                    Button("Forget This Project", role: .destructive) { orbit.forget(project: project.id) }
                }
            }
        }
    }

    @ViewBuilder private var projectDetail: some View {
        if let project = currentProject {
            VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
                HStack(spacing: NotchTokens.Spacing.s) {
                    Text(project.name).font(NotchTokens.Typography.headline).lineLimit(1)
                    let today = project.minutesByDay[OrbitPolicy.dayKey(Date())] ?? 0
                    if today > 0 { NotchBadge(text: "\(today)m today") }
                    Spacer(minLength: 0)
                    NotchIconButton(symbol: project.pinned ? "pin.slash" : "pin", help: project.pinned ? "Unpin" : "Pin") {
                        orbit.togglePin(project.id)
                    }
                    if let root = project.root {
                        NotchIconButton(symbol: "folder", help: "Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)])
                        }
                    }
                    if writeVault {
                        NotchIconButton(symbol: "book.closed", help: "Open the note in Obsidian") {
                            orbit.openInObsidian(orbit.noteURL(forProject: project))
                        }
                    }
                }
                let team = OrbitPolicy.topPeople(of: project, in: orbit.state, limit: 5)
                if !team.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(team) { person in
                            NotchChip(isSelected: false, action: { mode = .people; selectedPerson = person.id }) {
                                Text(person.name).font(NotchTokens.Typography.caption)
                            }
                        }
                    }
                }
                timeline(OrbitPolicy.events(for: project.id, in: orbit.state, limit: 30), showProject: false)
                NotchComposeField(placeholder: "Add a note to \(project.name)", text: $draft,
                                  onSend: { orbit.addNote(draft, project: project.id); draft = "" },
                                  isFocused: $noteFocused)
            }
        }
    }

    // MARK: People

    private var currentPerson: OrbitPerson? {
        let list = people
        return list.first { $0.id == selectedPerson } ?? list.first
    }

    private var peopleList: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(people) { person in
                listRow(title: person.name, detail: relative(person.lastSeen), symbol: "pin.fill",
                        selected: person.id == currentPerson?.id) {
                    selectedPerson = person.id
                }
                .contextMenu {
                    Button("Unpin \(person.name)") { orbit.unpin(person.id) }
                }
            }
        }
    }

    @ViewBuilder private var personDetail: some View {
        if let person = currentPerson {
            VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
                HStack(spacing: NotchTokens.Spacing.s) {
                    Text(person.name).font(NotchTokens.Typography.headline).lineLimit(1)
                    if let app = person.lastApp { NotchBadge(text: app) }
                    Spacer(minLength: 0)
                    NotchIconButton(symbol: "pin.slash", help: "Unpin") { orbit.unpin(person.id) }
                    if writeVault {
                        NotchIconButton(symbol: "book.closed", help: "Open the note in Obsidian") {
                            orbit.openInObsidian(orbit.noteURL(forPerson: person))
                        }
                    }
                }
                let linked = person.projects.sorted { $0.value > $1.value }.prefix(5).compactMap { orbit.state.projects[$0.key] }
                if !linked.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(linked) { project in
                            NotchChip(isSelected: false, action: { mode = .projects; selectedProject = project.id }) {
                                Text(project.name).font(NotchTokens.Typography.caption)
                            }
                        }
                    }
                }
                timeline(OrbitPolicy.events(forPerson: person.id, in: orbit.state, limit: 30), showProject: true)
            }
        }
    }

    // MARK: Pieces

    private func listRow(title: String, detail: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
                Text(title).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                Spacer(minLength: 4)
                Text(detail).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous)
                .fill(selected ? Color.white.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeline(_ events: [OrbitEvent], showProject: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                if events.isEmpty {
                    Text("Nothing yet.").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: event.kind.symbol).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 12)
                        Text(event.text).font(NotchTokens.Typography.body).lineLimit(2)
                        if showProject, let id = event.project, let project = orbit.state.projects[id] {
                            Text(project.name).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(relative(event.date)).font(NotchTokens.Typography.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let link = event.url, let url = URL(string: link) { NSWorkspace.shared.open(url) }
                    }
                    .contextMenu {
                        if linear.isActive {
                            Button("Create Linear Issue") {
                                Orbit.shared.sendToLinear(title: event.text, detail: "", project: event.project)
                            }
                        }
                    }
                }
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}
