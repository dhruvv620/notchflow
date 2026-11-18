// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

/// The AI Agents tab: what an agent is waiting on you for, and every running session.
struct NotchAgentsView: View {
    @ObservedObject private var hub = AgentHub.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var interactionToken = UUID()
    @State private var composing = false

    var body: some View {
        Group {
            if let request = hub.requests.first {
                VStack(alignment: .leading, spacing: NotchTokens.Spacing.m) {
                    AgentRequestCard(request: request)
                    if hub.requests.count > 1 {
                        Text("\(hub.requests.count - 1) more waiting")
                            .font(NotchTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
                    header
                    if composing {
                        AgentTaskComposer { composing = false }
                    }
                    if hub.sessions.isEmpty {
                        if !composing { emptyState }
                    } else {
                        sessionList
                    }
                }
            }
        }
        .notchTabPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: hub.requests.isEmpty) { _, empty in
            // Keep the notch open while you decide.
            vm.setAutoCloseSuppression(!empty, token: interactionToken)
        }
        .onChange(of: composing) { _, open in
            vm.setAutoCloseSuppression(open || !hub.requests.isEmpty, token: interactionToken)
        }
        .onAppear { vm.setAutoCloseSuppression(!hub.requests.isEmpty, token: interactionToken) }
        .onDisappear { vm.setAutoCloseSuppression(false, token: interactionToken) }
    }

    private var header: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Text("AI Agents").font(NotchTokens.Typography.title)
            if !hub.sessions.isEmpty {
                NotchBadge(text: "\(hub.sessions.count)")
            }
            Spacer(minLength: 0)
            NotchPillButton(title: composing ? "Cancel" : "New task", symbol: composing ? "xmark" : "plus", prominent: !composing) {
                withAnimation(NotchTokens.Motion.standard) { composing.toggle() }
            }
        }
    }

    private var emptyState: some View {
        let connected = AgentSetup.anyAgentConnected
        return NotchEmptyState(symbol: "sparkles", title: "No agents running",
                               detail: connected
                                   ? "Start one with New task, or in any terminal. Approvals, questions and progress show up here."
                                   : "Connect Claude Code, Codex, Cursor or Gemini in Settings > AI Agents to work with them from the notch.") {
            if !connected {
                NotchPillButton(title: "Set up", symbol: "gearshape") {
                    SettingsWindowController.shared.showWindow()
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: NotchTokens.Spacing.xs) {
                    ForEach(hub.sessions) { session in
                        AgentSessionRow(session: session)
                    }
                }
            }
        }
    }
}

// MARK: - Request card

private struct AgentRequestCard: View {
    let request: AgentRequest
    @ObservedObject private var hub = AgentHub.shared
    @State private var denying = false
    @State private var denyReason = ""
    @State private var selections: [String: String] = [:]
    @FocusState private var reasonFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.m) {
            header
            switch request.kind {
            case .permission(let title, let detail, let risk, let canAlwaysAllow):
                permission(title: title, detail: detail, risk: risk, canAlwaysAllow: canAlwaysAllow)
            case .question(let questions):
                questionView(questions)
            case .ask(let question, let options):
                Text(question)
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: NotchTokens.Spacing.m) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        AgentButton(title: option, prominent: index == 0) { hub.resolve(request, with: .choice(option)) }
                    }
                    Spacer(minLength: 0)
                    inWindowButton(label: "Dismiss")
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Image(systemName: request.agent.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(request.agent.displayName)
                .font(NotchTokens.Typography.headline)
            Text("· \(request.project)")
                .font(NotchTokens.Typography.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let waited = Int(context.date.timeIntervalSince(request.createdAt))
                let left = max(0, Defaults[.agentApprovalWaitSeconds] - waited)
                Text(left > 0 ? "\(left)s" : "")
                    .font(NotchTokens.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Then it asks in its own window instead")
            }
            if request.appBundleID != nil {
                NotchIconButton(symbol: "arrow.up.forward.app", help: "Show its window") {
                    hub.openWindow(bundleID: request.appBundleID)
                }
            }
        }
    }

    @ViewBuilder
    private func permission(title: String, detail: String, risk: AgentRisk, canAlwaysAllow: Bool) -> some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            if let label = risk.label {
                NotchBadge(text: label, tint: risk == .danger ? .red : .orange, filled: risk == .danger)
            }
        }
        if !detail.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 64)
            .padding(NotchTokens.Spacing.m)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous))
        }
        if denying {
            NotchComposeField(placeholder: "Tell Claude what to do instead (optional)", text: $denyReason,
                              onSend: deny, onCancel: { denying = false }, isFocused: $reasonFocused)
                .onAppear { reasonFocused = true }
            HStack(spacing: NotchTokens.Spacing.m) {
                AgentButton(title: "Deny", symbol: "xmark", destructive: true, action: deny)
                AgentButton(title: "Back") { denying = false }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: NotchTokens.Spacing.m) {
                AgentButton(title: "Allow", symbol: "checkmark", prominent: true) { hub.resolve(request, with: .allow) }
                if canAlwaysAllow {
                    AgentButton(title: "Always allow", symbol: "checkmark.seal") { hub.resolve(request, with: .allowAlways) }
                        .help("Claude Code adds a rule so it does not ask again for this")
                }
                AgentButton(title: "Deny", symbol: "xmark", destructive: true) { denying = true }
                Spacer(minLength: 0)
                inWindowButton(label: "Ask in its window")
            }
        }
    }

    @ViewBuilder
    private func questionView(_ questions: [AgentQuestion]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: NotchTokens.Spacing.m) {
                ForEach(questions, id: \.question) { question in
                    VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
                        Text(question.question)
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        FlowOptions(question: question, selection: Binding(
                            get: { selections[question.question] },
                            set: { selections[question.question] = $0 }
                        ))
                    }
                }
            }
        }
        HStack(spacing: NotchTokens.Spacing.m) {
            let complete = questions.allSatisfy { selections[$0.question] != nil }
            AgentButton(title: "Send answer", symbol: "arrow.up", prominent: true) {
                hub.resolve(request, with: .answers(selections))
            }
            .disabled(!complete)
            .opacity(complete ? 1 : 0.5)
            Spacer(minLength: 0)
            inWindowButton(label: "Answer in its window")
        }
    }

    private func deny() {
        let reason = denyReason.trimmingCharacters(in: .whitespacesAndNewlines)
        hub.resolve(request, with: .deny(reason.isEmpty ? "The user declined this from NotchFlow." : reason))
    }

    private func inWindowButton(label: String) -> some View {
        Button(label) {
            hub.resolve(request, with: .inWindow)
            hub.openWindow(bundleID: request.appBundleID)
        }
        .buttonStyle(.plain)
        .font(NotchTokens.Typography.caption)
        .foregroundStyle(.secondary)
    }
}

/// The options of one question as tappable chips; multi-select joins choices with ", ".
private struct FlowOptions: View {
    let question: AgentQuestion
    @Binding var selection: String?

    private var chosen: Set<String> {
        Set((selection ?? "").components(separatedBy: ", ").filter { !$0.isEmpty })
    }

    var body: some View {
        HStack(spacing: NotchTokens.Spacing.xs) {
            ForEach(question.options, id: \.label) { option in
                NotchChip(isSelected: chosen.contains(option.label), action: { toggle(option.label) }) {
                    Text(option.label).lineLimit(1)
                }
                .help(option.description)
            }
        }
    }

    private func toggle(_ label: String) {
        guard question.multiSelect else { selection = label; return }
        var set = chosen
        if set.contains(label) { set.remove(label) } else { set.insert(label) }
        let ordered = question.options.map(\.label).filter(set.contains)
        selection = ordered.isEmpty ? nil : ordered.joined(separator: ", ")
    }
}

private struct AgentButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var destructive = false
    let action: () -> Void
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(fill))
            .foregroundStyle(prominent ? appearance.accentForegroundColor : (destructive ? Color.red : Color.primary))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fill: Color {
        if prominent { return appearance.accentColor.opacity(hovering ? 1 : 0.88) }
        if destructive { return Color.red.opacity(hovering ? 0.22 : 0.14) }
        return Color.white.opacity(hovering ? 0.16 : 0.1)
    }
}

// MARK: - Sessions

private struct AgentSessionRow: View {
    let session: AgentSession
    @ObservedObject private var hub = AgentHub.shared
    @State private var replying = false
    @State private var reply = ""
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.xs) {
            NotchRow(title: session.project, subtitle: subtitle, action: {
                if hub.canReply(to: session) {
                    withAnimation(NotchTokens.Motion.standard) { replying.toggle() }
                } else {
                    hub.openWindow(bundleID: session.appBundleID)
                }
            }) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 24, height: 24)
                    if session.isWorking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                    }
                }
            } trailing: {
                HStack(spacing: NotchTokens.Spacing.xs) {
                    if let started = session.turnStartedAt, session.isWorking {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(since: started, now: context.date))
                                .font(NotchTokens.Typography.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if hub.canReply(to: session) {
                        NotchIconButton(symbol: "arrowshape.turn.up.left", help: "Reply from the notch", size: 18) {
                            withAnimation(NotchTokens.Motion.standard) { replying.toggle() }
                        }
                    }
                    if session.appBundleID != nil {
                        NotchIconButton(symbol: "arrow.up.forward.app", help: "Show its window", size: 18) {
                            hub.openWindow(bundleID: session.appBundleID)
                        }
                    }
                    NotchIconButton(symbol: "xmark", help: "Remove from the list", size: 18) { hub.dismiss(session) }
                }
            }
            if replying && hub.canReply(to: session) {
                NotchComposeField(placeholder: "Reply to \(session.agent.displayName) in \(session.project)", text: $reply,
                                  onSend: send, onCancel: { replying = false }, isFocused: $replyFocused)
                    .padding(.leading, 30)
                    .onAppear { replyFocused = true }
            }
        }
        .help(session.lastPrompt.map { "Asked: \($0)" } ?? session.cwd)
        .onChange(of: hub.canReply(to: session)) { _, canReply in if !canReply { replying = false } }
    }

    private func send() {
        hub.reply(to: session, text: reply)
        reply = ""
        replying = false
    }

    private var subtitle: String {
        switch session.state {
        case .ready: return "\(session.agent.displayName) · Ready"
        case .working(let activity): return "\(session.agent.displayName) · \(activity)"
        case .waiting(let reason): return "Needs you · \(reason)"
        case .done(let summary): return "Done · \(summary)"
        }
    }

    private var symbol: String {
        switch session.state {
        case .ready: return "circle"
        case .working: return "ellipsis"
        case .waiting: return "exclamationmark"
        case .done: return "checkmark"
        }
    }

    private var color: Color {
        switch session.state {
        case .ready: return .secondary
        case .working: return .white
        case .waiting: return .orange
        case .done: return .green
        }
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}

// MARK: - Closed notch

/// Under the closed notch: an agent needs you (amber), just finished (green), or is working.
struct AgentLiveActivity: View {
    @ObservedObject private var hub = AgentHub.shared
    let isHovering: Bool
    @State private var pulse = false

    var body: some View {
        if let request = hub.requests.first {
            ClosedNotchWings(isHovering: isHovering) {
                Image(systemName: request.agent.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .opacity(pulse ? 1 : 0.5)
                Text(request.project)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            } trailing: {
                Text(hub.requests.count > 1 ? "\(hub.requests.count) waiting" : label(for: request))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(request.agent.displayName) in \(request.project) needs you")
        } else if let waiting = hub.waitingInWindowSessions.first {
            ClosedNotchWings(isHovering: isHovering) {
                Image(systemName: waiting.agent.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .opacity(pulse ? 1 : 0.5)
                Text(waiting.project)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            } trailing: {
                Text("Needs you")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.orange)
            }
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
            .onTapGesture { hub.openWindow(bundleID: waiting.appBundleID) }
            .help("\(waiting.agent.displayName) is asking in its window")
        } else if let done = hub.announcement {
            ClosedNotchWings(isHovering: isHovering) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text(done.project)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            } trailing: {
                Text(doneLabel(done))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        } else if let working = hub.workingSessions.first {
            ClosedNotchWings(isHovering: isHovering) {
                ProgressView().controlSize(.mini).tint(.white).frame(width: 12, height: 12)
                Text(working.project)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            } trailing: {
                if case .working(let activity) = working.state {
                    Text(hub.workingSessions.count > 1 ? "\(hub.workingSessions.count) agents" : activity)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
    }

    private func label(for request: AgentRequest) -> String {
        switch request.kind {
        case .permission: return "Approve?"
        case .question: return "Question"
        case .ask: return "Asks you"
        }
    }

    private func doneLabel(_ session: AgentSession) -> String {
        if case .done(let summary) = session.state, session.agent == .script, !summary.isEmpty { return summary }
        return "Done"
    }
}

// MARK: - New task

/// Starts an agent with a first prompt in a new Terminal or iTerm window.
private struct AgentTaskComposer: View {
    let onStarted: () -> Void
    @ObservedObject private var hub = AgentHub.shared
    @Default(.agentLaunchAgent) private var agentValue
    @Default(.agentRecentProjects) private var recentProjects
    @State private var directory = ""
    @State private var prompt = ""
    @FocusState private var promptFocused: Bool

    private var agent: AgentHookPolicy.LaunchAgent { AgentHookPolicy.LaunchAgent(rawValue: agentValue) ?? .claude }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            HStack(spacing: NotchTokens.Spacing.s) {
                Menu {
                    ForEach(AgentHookPolicy.LaunchAgent.allCases, id: \.rawValue) { option in
                        Button(option.title) { agentValue = option.rawValue }
                    }
                } label: {
                    Label(agent.title, systemImage: "sparkles")
                        .font(NotchTokens.Typography.captionEmphasis)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text("in").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(recentProjects, id: \.self) { path in
                        Button((path as NSString).lastPathComponent) { directory = path }
                    }
                    if !recentProjects.isEmpty { Divider() }
                    Button("Choose a folder…", action: chooseFolder)
                    Button("Home folder") { directory = "" }
                } label: {
                    Label(directory.isEmpty ? "Home folder" : (directory as NSString).lastPathComponent, systemImage: "folder")
                        .font(NotchTokens.Typography.captionEmphasis)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer(minLength: 0)
            }
            NotchComposeField(placeholder: "What should \(agent.title) do?", text: $prompt, onSend: start,
                              onCancel: onStarted, isFocused: $promptFocused)
            if let error = hub.launchError {
                Text(error).font(NotchTokens.Typography.caption).foregroundStyle(.orange).lineLimit(2)
            } else {
                Text("Opens in \(Defaults[.agentTerminalApp]) so you can watch it; its approvals and progress come back here.")
                    .font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
            }
        }
        .padding(NotchTokens.Spacing.m)
        .background { NotchElementSurface(cornerRadius: NotchTokens.Radius.card) }
        .onAppear {
            if directory.isEmpty { directory = recentProjects.first ?? "" }
            promptFocused = true
        }
    }

    private func start() {
        hub.startTask(agent: agent, prompt: prompt, directory: directory)
        prompt = ""
        onStarted()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            directory = url.path
            hub.rememberProject(url.path)
        }
    }
}
