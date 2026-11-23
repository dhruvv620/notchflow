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

    enum Mode: String, CaseIterable {
        case loops, projects, people
        var title: String { rawValue.capitalized }
    }
    @State private var mode: Mode = .loops
    @State private var selectedProject: String?
    @State private var selectedPerson: String?
    @State private var draft = ""
    @State private var interactionToken = UUID()
    @FocusState private var noteFocused: Bool

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
                    NotchEmptyState(symbol: "person.2", title: "No people yet",
                                    detail: "People appear when they message you or you make them a promise.")
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
        .onChange(of: noteFocused) { _, focused in
            vm.setAutoCloseSuppression(focused, token: interactionToken)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: interactionToken) }
    }

    private var modes: [Mode] {
        Mode.allCases.filter { mode in
            switch mode {
            case .loops: return showLoops
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
            if linear.isActive && loop.kind != .linear {
                Button("Create Linear Issue") {
                    Orbit.shared.sendToLinear(title: loop.title, detail: loop.detail, project: loop.project)
                }
            }
        }
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
                listRow(title: person.name, detail: relative(person.lastSeen), symbol: "person.crop.circle",
                        selected: person.id == currentPerson?.id) {
                    selectedPerson = person.id
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
