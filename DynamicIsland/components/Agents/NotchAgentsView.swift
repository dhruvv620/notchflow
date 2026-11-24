// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI

/// The AI Agents tab: approvals first; otherwise your sessions on the left
/// and the open conversation on the right, where you can keep it going.
struct NotchAgentsView: View {
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var conversations = AgentConversations.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var interactionToken = UUID()
    @State private var composing = false
    @Default(.agentPanelSize) private var panelSizeValue
    private var panelSize: AgentPanelSize { AgentPanelSize(rawValue: panelSizeValue) ?? .regular }

    @Default(.agentTabFilter) private var filter
    private var filterKind: AgentKind? { AgentKind(rawValue: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            AgentFilterBar(filter: $filter, composing: $composing)
            if let kind = filterKind {
                agentView(kind)
            } else {
                AgentBoard { session in open(session) }
            }
        }
        .notchTabPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: hub.requests.isEmpty) { _, _ in updateSuppression() }
        .onChange(of: filter) { _, _ in selectFirstSession() }
        .onChange(of: composing) { _, _ in updateSuppression() }
        .onAppear {
            conversations.refreshList(force: true)
            if let selected = conversations.selected { conversations.select(selected) }
            selectFirstSession()
            updateSuppression()
        }
        .onDisappear {
            conversations.stopFollowing()
            vm.setAutoCloseSuppression(false, token: interactionToken)
        }
    }

    /// One agent's tab: its approvals first, else its sessions beside the open one.
    @ViewBuilder private func agentView(_ kind: AgentKind) -> some View {
        if let request = hub.requests.first(where: { $0.agent == kind }) {
            VStack(alignment: .leading, spacing: NotchTokens.Spacing.m) {
                AgentRequestCard(request: request)
                let more = hub.requests.filter { $0.agent == kind }.count - 1
                if more > 0 {
                    Text("\(more) more waiting").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(alignment: .top, spacing: NotchTokens.Spacing.m) {
                AgentSessionList(composing: $composing, panelSizeValue: $panelSizeValue, kind: kind)
                    .frame(width: panelSize.listWidth)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                Group {
                    if composing {
                        AgentTaskComposer { withAnimation(NotchTokens.Motion.standard) { composing = false } }
                    } else if let selected = conversations.selected, kind.readsTranscripts,
                              selected.agent == (kind == .codex ? .codex : .claude) {
                        AgentChatView(summary: selected, textScale: panelSize.textScale)
                    } else if !kind.readsTranscripts || hub.sessions.contains(where: { $0.agent == kind }) {
                        // Its running sessions as cards (Gemini CLI and Cursor keep
                        // their chat in their own window; Open shows a conversation).
                        let live = hub.sessions.filter { $0.agent == kind }
                        if live.isEmpty {
                            NotchEmptyState(symbol: kind.symbol, title: "No \(kind.displayName) sessions",
                                            detail: "Start one with its icon above. Its approvals and status show here; the conversation stays in its window.")
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                                    ForEach(live) { session in AgentWorkCard(session: session) { open(session) } }
                                }
                            }
                        }
                    } else {
                        NotchEmptyState(symbol: kind.symbol,
                                        title: hub.sessions.contains { $0.agent == kind } ? "Pick a session" : "No \(kind.displayName) sessions yet",
                                        detail: "Pick one on the left to see its conversation and keep it going, or start a New task.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// On an agent's tab, opens its newest conversation when none of its own is open.
    private func selectFirstSession() {
        guard let kind = filterKind, kind.readsTranscripts else { return }
        let agent: AgentSessionSummary.Agent = kind == .codex ? .codex : .claude
        if conversations.selected?.agent == agent { return }
        if let live = hub.sessions.first(where: { $0.agent == kind }) {
            conversations.select(sessionID: live.id, cwd: live.cwd, agent: agent)
        } else if let recent = conversations.recent.first(where: { $0.agent == agent }) {
            conversations.select(recent)
        }
    }

    /// Opens a session: its conversation for Claude Code and Codex, else its window.
    private func open(_ session: AgentSession) {
        if session.agent.readsTranscripts {
            filter = session.agent.rawValue
            composing = false
            conversations.select(sessionID: session.id, cwd: session.cwd,
                                 agent: session.agent == .codex ? .codex : .claude)
        } else {
            hub.openWindow(bundleID: session.appBundleID)
        }
    }

    /// Keep the notch open while you decide or type.
    private func updateSuppression() {
        vm.setAutoCloseSuppression(composing || !hub.requests.isEmpty, token: interactionToken)
    }
}

// MARK: - Request card

private struct AgentRequestCard: View {
    let request: AgentRequest
    /// Narrow column (the All board): shorter labels, buttons wrap under the command.
    var compact = false
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
        } else if compact {
            VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
                HStack(spacing: NotchTokens.Spacing.s) {
                    AgentButton(title: "Allow", symbol: "checkmark", prominent: true, compact: true) { hub.resolve(request, with: .allow) }
                    if canAlwaysAllow {
                        AgentButton(title: "Always", symbol: "checkmark.seal", compact: true) { hub.resolve(request, with: .allowAlways) }
                            .help("Claude Code adds a rule so it does not ask again for this")
                    }
                    AgentButton(title: "Deny", symbol: "xmark", destructive: true, compact: true) { denying = true }
                    Spacer(minLength: 0)
                }
                inWindowButton(label: "Ask in its window")
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
    var compact = false
    let action: () -> Void
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 4 : 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 7)
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

// MARK: - Session list

private struct AgentSessionList: View {
    @Binding var composing: Bool
    @Binding var panelSizeValue: Int
    /// Only this agent's sessions (nil: all).
    var kind: AgentKind? = nil
    private var panelSize: AgentPanelSize { AgentPanelSize(rawValue: panelSizeValue) ?? .regular }
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var conversations = AgentConversations.shared

    private var liveSessions: [AgentSession] {
        guard let kind else { return hub.sessions }
        return hub.sessions.filter { $0.agent == kind }
    }

    private var recentOnly: [AgentSessionSummary] {
        let live = Set(hub.sessions.map(\.id))
        return conversations.recent.filter { summary in
            guard !live.contains(summary.id) else { return false }
            switch kind {
            case nil: return true
            case .claudeCode?: return summary.agent == .claude
            case .codex?: return summary.agent == .codex
            default: return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            HStack(spacing: NotchTokens.Spacing.s) {
                Text(kind?.displayName ?? "AI Agents").font(NotchTokens.Typography.title).lineLimit(1)
                Spacer(minLength: 0)
                sizeMenu
                NotchPillButton(title: "New", symbol: "plus", prominent: !composing) {
                    if let launch = kind?.launchAgent { Defaults[.agentLaunchAgent] = launch.rawValue }
                    withAnimation(NotchTokens.Motion.standard) { composing.toggle() }
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if conversations.startingNewSession {
                        AgentListRow(symbol: "sparkle", title: "Starting…", subtitle: "New session", tint: .white,
                                     busy: true, selected: false) {}
                    }
                    if !liveSessions.isEmpty {
                        NotchSectionHeader(title: "Live")
                        ForEach(liveSessions) { session in
                            AgentListRow(symbol: session.agent.symbol, title: session.project, subtitle: liveSubtitle(session),
                                         tint: tint(session.state), busy: session.isWorking || conversations.isRunning(session.id),
                                         selected: conversations.selected?.id == session.id) {
                                composing = false
                                if session.agent == .claudeCode || session.agent == .codex {
                                    conversations.select(sessionID: session.id, cwd: session.cwd, agent: session.agent == .codex ? .codex : .claude)
                                } else {
                                    hub.openWindow(bundleID: session.appBundleID)
                                }
                            }
                        }
                    }
                    if !recentOnly.isEmpty {
                        NotchSectionHeader(title: "Recent")
                        ForEach(recentOnly) { summary in
                            AgentListRow(symbol: summary.agent == .claude ? AgentKind.claudeCode.symbol : AgentKind.codex.symbol,
                                         title: summary.project, subtitle: summary.title, tint: .secondary,
                                         busy: conversations.isRunning(summary.id),
                                         selected: conversations.selected?.id == summary.id) {
                                composing = false
                                conversations.select(summary)
                            }
                        }
                    }
                    if liveSessions.isEmpty && recentOnly.isEmpty && !conversations.startingNewSession {
                        Text(kind == nil || kind?.readsTranscripts == true
                             ? "Sessions from the last two weeks appear here."
                             : "Running sessions appear here.")
                            .font(NotchTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, NotchTokens.Spacing.s)
                    }
                }
            }
        }
    }

    /// Click to make the tab bigger (Regular, Large, Extra large), hold for the list.
    private var sizeMenu: some View {
        Menu {
            ForEach(AgentPanelSize.allCases, id: \.rawValue) { size in
                Button {
                    applyNotchLayoutChange { panelSizeValue = size.rawValue }
                } label: {
                    if size == panelSize { Label(size.title, systemImage: "checkmark") } else { Text(size.title) }
                }
            }
        } label: {
            Image(systemName: panelSize == .extraLarge
                  ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .medium))
        } primaryAction: {
            applyNotchLayoutChange { panelSizeValue = panelSize.next.rawValue }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Size: \(panelSize.title). Click to make AI Agents bigger; hold for sizes.")
    }

    private func liveSubtitle(_ session: AgentSession) -> String {
        switch session.state {
        case .ready: return "Ready"
        case .working(let activity): return activity
        case .waiting(let reason): return "Needs you · \(reason)"
        case .done(let summary): return "Done · \(summary)"
        }
    }

    private func tint(_ state: AgentSession.State) -> Color {
        switch state {
        case .ready: return .secondary
        case .working: return .white
        case .waiting: return .orange
        case .done: return .green
        }
    }
}

private struct AgentListRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    let busy: Bool
    let selected: Bool
    let action: () -> Void
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: NotchTokens.Spacing.s) {
                ZStack {
                    Circle().fill(tint.opacity(0.16)).frame(width: 22, height: 22)
                    if busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                    Text(subtitle).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous)
                .fill(selected ? appearance.accentColor.opacity(0.22) : Color.white.opacity(hovering ? 0.08 : 0.03)))
            .contentShape(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Conversation

private struct AgentChatView: View {
    let summary: AgentSessionSummary
    /// Bigger panel sizes read in bigger text.
    var textScale: CGFloat = 1
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var conversations = AgentConversations.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var draft = ""
    @State private var expandedGroups: Set<String> = []
    @FocusState private var focused: Bool

    private enum Row: Identifiable {
        case message(AgentChatItem)
        case tools([AgentChatItem])
        var id: String {
            switch self {
            case .message(let item): return item.id
            case .tools(let items): return "tools-" + (items.first?.id ?? "")
            }
        }
    }

    /// Consecutive tool steps fold into one line so the conversation stays readable.
    private var rows: [Row] {
        var rows: [Row] = []
        var tools: [AgentChatItem] = []
        for item in conversations.items {
            if item.role == .tool {
                tools.append(item)
            } else {
                if !tools.isEmpty { rows.append(.tools(tools)); tools = [] }
                rows.append(.message(item))
            }
        }
        if !tools.isEmpty { rows.append(.tools(tools)) }
        return rows
    }

    private var live: AgentSession? { hub.sessions.first { $0.id == summary.id } }
    private var isBusy: Bool { conversations.isRunning(summary.id) || live?.isWorking == true }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            header
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
                        ForEach(rows) { row in
                            switch row {
                            case .message(let item): bubble(item.text, mine: item.role == .user)
                            case .tools(let items): toolGroup(items)
                            }
                        }
                        ForEach(Array(conversations.pendingMessages.enumerated()), id: \.offset) { _, text in
                            bubble(text, mine: true).opacity(0.6)
                        }
                        if isBusy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text(workingText).font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conversations.items.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: conversations.pendingMessages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if let error = conversations.lastError {
                Text(error).font(NotchTokens.Typography.caption).foregroundStyle(.orange).lineLimit(2).textSelection(.enabled)
            }
            NotchComposeField(placeholder: placeholder, text: $draft, isSending: conversations.isRunning(summary.id),
                              isEnabled: conversations.canSend, onSend: send, isFocused: $focused)
        }
    }

    private var header: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Image(systemName: summary.agent == .claude ? AgentKind.claudeCode.symbol : AgentKind.codex.symbol)
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(summary.project).font(NotchTokens.Typography.headline).lineLimit(1)
                Text(summary.title).font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if conversations.isRunning(summary.id) {
                NotchPillButton(title: "Stop", symbol: "stop.fill") { conversations.stop(summary.id) }
            }
            if let app = live?.appBundleID {
                NotchIconButton(symbol: "arrow.up.forward.app", help: "Show its terminal") { hub.openWindow(bundleID: app) }
            }
        }
    }

    private var workingText: String {
        if case .working(let activity) = live?.state { return activity }
        return "Working…"
    }

    private var placeholder: String {
        let name = summary.agent == .claude ? "Claude" : "Codex"
        if conversations.isRunning(summary.id) { return "\(name) is working…" }
        if let live, live.isWorking { return "\(name) is working in its terminal…" }
        return "Message \(name) in \(summary.project)"
    }

    private func send() {
        conversations.send(draft)
        draft = ""
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(LocalizedStringKey(text))
                .font(.system(size: 12 * textScale))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(mine ? appearance.accentColor.opacity(0.28) : Color.white.opacity(0.07)))
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func toolGroup(_ items: [AgentChatItem]) -> some View {
        let key = items.first?.id ?? ""
        let expanded = expandedGroups.contains(key)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                if expanded { expandedGroups.remove(key) } else { expandedGroups.insert(key) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                    Text(items.count == 1 ? items[0].text : "\(items.count) steps · \(items.last?.text ?? "")")
                        .lineLimit(1)
                }
                .font(.system(size: 10 * textScale, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if expanded && items.count > 1 {
                ForEach(items) { item in
                    Text(item.text)
                        .font(.system(size: 10 * textScale, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 13)
                }
            }
        }
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
                // Allow / Deny live on the approval card beside the notch
                // (AgentApprovalCard): hovering here opens the notch.
                Text(hub.requests.count > 1 ? "\(hub.requests.count) waiting" : label(for: request))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }
            .onAppear { withAnimation(EnergyState.repeating(.easeInOut(duration: 0.9))) { pulse = true } }
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
            .onAppear { withAnimation(EnergyState.repeating(.easeInOut(duration: 0.9))) { pulse = true } }
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
            let all = hub.workingSessions
            ClosedNotchWings(isHovering: isHovering) {
                if all.count > 1 {
                    // One dot per running agent, in its colour.
                    HStack(spacing: 3) {
                        ForEach(all.prefix(6)) { session in
                            Circle().fill(session.agent.tint).frame(width: 7, height: 7)
                                .opacity(pulse ? 1 : 0.55)
                        }
                    }
                    .onAppear { withAnimation(EnergyState.repeating(.easeInOut(duration: 1.2))) { pulse = true } }
                } else {
                    ProgressView().controlSize(.mini).tint(working.agent.tint).frame(width: 12, height: 12)
                    Text(working.project)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            } trailing: {
                if all.count > 1 {
                    Text("\(all.count) working")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                } else if case .working(let activity) = working.state {
                    Text(activity)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(all.count > 1 ? "\(all.count) agents working" : "\(working.agent.displayName) working in \(working.project)")
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

/// Starts an agent with a first prompt: here in the notch (Claude Code,
/// Codex), or in a new Terminal or iTerm window.
private struct AgentTaskComposer: View {
    let onStarted: () -> Void
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var conversations = AgentConversations.shared
    @Default(.agentLaunchAgent) private var agentValue
    @Default(.agentRecentProjects) private var recentProjects
    @Default(.agentRunInTerminal) private var runInTerminal
    @State private var directory = ""
    @State private var prompt = ""
    @FocusState private var promptFocused: Bool

    private var agent: AgentHookPolicy.LaunchAgent { AgentHookPolicy.LaunchAgent(rawValue: agentValue) ?? .claude }
    /// Gemini CLI and Cursor Agent run in a terminal; their sessions aren't read here yet.
    private var runsHere: Bool { !runInTerminal && (agent == .claude || agent == .codex) }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.m) {
            Text("New task").font(NotchTokens.Typography.title)
            HStack(spacing: NotchTokens.Spacing.s) {
                Menu {
                    ForEach(AgentHookPolicy.LaunchAgent.allCases, id: \.rawValue) { option in
                        Button(option.title) { agentValue = option.rawValue }
                    }
                } label: {
                    Label(agent.title, systemImage: "sparkles").font(NotchTokens.Typography.captionEmphasis)
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
            Toggle(isOn: $runInTerminal) {
                Text("Open in \(Defaults[.agentTerminalApp]) instead").font(NotchTokens.Typography.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(agent == .gemini || agent == .cursor)
            Text(runsHere
                 ? "Runs here in the notch: the conversation, its progress and its approvals stay in this tab."
                 : "Opens in \(Defaults[.agentTerminalApp]); its progress and approvals still come back here.")
                .font(NotchTokens.Typography.caption)
                .foregroundStyle(.secondary)
            if let error = hub.launchError {
                Text(error).font(NotchTokens.Typography.caption).foregroundStyle(.orange).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            if directory.isEmpty { directory = recentProjects.first ?? "" }
            promptFocused = true
        }
    }

    private func start() {
        if runsHere {
            conversations.start(agent: agent == .codex ? .codex : .claude, prompt: prompt, directory: directory)
        } else {
            hub.startTask(agent: agent, prompt: prompt, directory: directory)
        }
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

// MARK: - Agents as a team

extension AgentKind {
    /// The agent's colour, the same everywhere (tabs, cards, closed-notch dots).
    var tint: Color {
        switch self {
        case .claudeCode: return Color(red: 0.88, green: 0.54, blue: 0.37)
        case .codex: return Color(red: 0.25, green: 0.75, blue: 0.61)
        case .gemini: return Color(red: 0.44, green: 0.61, blue: 1.0)
        case .cursor: return Color(red: 0.71, green: 0.55, blue: 1.0)
        case .script: return Color(white: 0.75)
        }
    }

    var monogram: String {
        switch self {
        case .claudeCode: return "C"
        case .codex: return "X"
        case .gemini: return "G"
        case .cursor: return "U"
        case .script: return "S"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .gemini: return "Gemini"
        default: return displayName
        }
    }

    /// Claude Code and Codex keep session files NotchFlow can read and continue.
    var readsTranscripts: Bool { self == .claudeCode || self == .codex }

    var launchAgent: AgentHookPolicy.LaunchAgent? {
        switch self {
        case .claudeCode: return .claude
        case .codex: return .codex
        case .gemini: return .gemini
        case .cursor: return .cursor
        case .script: return nil
        }
    }

    static let teamOrder: [AgentKind] = [.claudeCode, .codex, .gemini, .cursor]
}

private func agentColor(hex: String) -> Color {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
    return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

/// All · Claude · Codex · Gemini · Cursor, then the Start icons.
private struct AgentFilterBar: View {
    @Binding var filter: String
    @Binding var composing: Bool
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var tools = AgentTools.shared
    @ObservedObject private var jobs = OrbitJobs.shared
    @Default(.agentToolsShown) private var shownIDs

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    tab(title: "All", kind: nil, count: hub.sessions.count + reviewCount,
                        needsYou: !hub.requests.isEmpty || !hub.waitingInWindowSessions.isEmpty)
                    ForEach(AgentKind.teamOrder, id: \.self) { kind in
                        tab(title: kind.shortName, kind: kind, count: hub.sessions.filter { $0.agent == kind }.count,
                            needsYou: hub.requests.contains { $0.agent == kind } || hub.sessions.contains { $0.agent == kind && $0.isWaiting })
                    }
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(tools.shown) { tool in AgentStartButton(tool: tool) }
                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }
                .buttonStyle(.plain)
                .help("Add or choose tools in Settings › AI Agents")
            }
        }
        .onAppear { tools.checkIfNeeded() }
    }

    private var reviewCount: Int { jobs.isActive ? jobs.reviewCount : 0 }

    private func tab(title: String, kind: AgentKind?, count: Int, needsYou: Bool) -> some View {
        let selected = (kind?.rawValue ?? "") == filter
        return Button {
            withAnimation(NotchTokens.Motion.standard) {
                filter = kind?.rawValue ?? ""
                composing = false
            }
        } label: {
            HStack(spacing: 5) {
                if let kind { Circle().fill(kind.tint).frame(width: 7, height: 7) }
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
                if count > 0 {
                    Text("\(count)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                }
                if needsYou { Circle().fill(Color.orange).frame(width: 5, height: 5) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? (kind?.tint ?? .white).opacity(0.2) : Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(selected ? (kind?.tint ?? .white).opacity(0.45) : .clear, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One tool's Start icon: pick a folder and it starts there, in the notch's
/// Terminal tab (hold ⌥ for your terminal app).
private struct AgentStartButton: View {
    let tool: AgentTool
    @ObservedObject private var tools = AgentTools.shared

    private var notInstalled: Bool { tools.hasChecked && !tools.installed.contains(tool.id) }
    private var optionDown: Bool { NSEvent.modifierFlags.contains(.option) }

    var body: some View {
        Menu {
            if notInstalled {
                Text("\(tool.name) wasn't found on this Mac")
                if !tool.install.isEmpty {
                    Button("Install \(tool.name)…") { tools.install(tool) }
                }
                Button("Check Again") { Task { await tools.check() } }
                Divider()
            }
            Section("Start \(tool.name) in") {
                ForEach(tools.folders(for: tool), id: \.self) { folder in
                    Button((folder as NSString).lastPathComponent) {
                        tools.launch(tool, in: folder, external: optionDown)
                    }
                }
                Button("Choose Folder…") { tools.chooseFolderAndLaunch(tool, external: optionDown) }
            }
            Divider()
            Text("Hold ⌥ to open it in your terminal app")
        } label: {
            Text(tool.monogram)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(agentColor(hex: tool.color).opacity(notInstalled ? 0.45 : 1))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(notInstalled ? "\(tool.name) isn't installed" : "Start \(tool.name) in a project")
    }
}

/// "All": what needs you on the left, every agent at work on the right.
private struct AgentBoard: View {
    let onOpen: (AgentSession) -> Void
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var jobs = OrbitJobs.shared

    private var reviews: [OrbitJob] { jobs.isActive ? jobs.jobs.filter { $0.state == .review } : [] }
    private var members: [AgentSession] {
        hub.sessions.sorted { a, b in
            (rank(a), b.updatedAt) < (rank(b), a.updatedAt)
        }
    }
    private func rank(_ session: AgentSession) -> Int { session.isWaiting ? 0 : session.isWorking ? 1 : 2 }

    var body: some View {
        if hub.requests.isEmpty && hub.waitingInWindowSessions.isEmpty && reviews.isEmpty && members.isEmpty {
            NotchEmptyState(symbol: "person.3", title: "No agents at work",
                            detail: "Start one with an icon above: pick a project and it opens right here in the Terminal tab. Running agents, their approvals and finished work show up on this board.")
        } else {
            HStack(alignment: .top, spacing: 10) {
                needsYou.frame(width: 290)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        NotchSectionHeader(title: "Working now")
                        if members.isEmpty {
                            Text("No sessions running.").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(members) { session in AgentWorkCard(session: session) { onOpen(session) } }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var needsYou: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                NotchSectionHeader(title: "Needs you")
                if hub.requests.isEmpty && hub.waitingInWindowSessions.isEmpty {
                    Text("Nothing is waiting on you.").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                }
                ForEach(hub.requests) { request in
                    AgentRequestCard(request: request, compact: true)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous)
                            .fill(request.agent.tint.opacity(0.1)))
                }
                ForEach(hub.waitingInWindowSessions) { session in
                    Button { hub.openWindow(bundleID: session.appBundleID) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(session.agent.tint).frame(width: 7, height: 7)
                            Text("\(session.agent.shortName) · \(session.project)").font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("Asking in its window").font(NotchTokens.Typography.caption).foregroundStyle(.orange)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous).fill(Color.orange.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                if !reviews.isEmpty {
                    NotchSectionHeader(title: "Ready for review").padding(.top, 4)
                    ForEach(reviews) { job in AgentReviewRow(job: job) }
                }
            }
        }
    }
}

/// A finished background hand-off, from the board.
private struct AgentReviewRow: View {
    let job: OrbitJob
    @ObservedObject private var jobs = OrbitJobs.shared

    var body: some View {
        let agent = AgentHookPolicy.LaunchAgent(rawValue: job.agent)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(agent?.title ?? job.agent) · \(job.title)").font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
            }
            Text(job.changes.summary).font(NotchTokens.Typography.caption).foregroundStyle(.green)
            HStack(spacing: 6) {
                NotchPillButton(title: "See changes", symbol: "doc.text.magnifyingglass") { jobs.seeChanges(job) }
                if job.branch != nil && !job.changes.isEmpty {
                    NotchPillButton(title: "Commit", symbol: "checkmark.circle", prominent: true) {
                        Task { await jobs.apply(job, commit: true) }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    DynamicIslandViewCoordinator.shared.currentView = .orbit
                    Orbit.shared.requestedTabMode = "team"
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("More in Orbit › Team (apply, keep going, throw away)")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous).fill(Color.green.opacity(0.08)))
    }

    private var tint: Color {
        switch job.agent {
        case "codex": return AgentKind.codex.tint
        default: return AgentKind.claudeCode.tint
        }
    }
}

/// One agent at work: who, where, what it's doing now, for how long.
private struct AgentWorkCard: View {
    let session: AgentSession
    let onOpen: () -> Void
    @ObservedObject private var hub = AgentHub.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(session.agent.monogram)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(session.agent.tint)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(session.agent.tint.opacity(0.18)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.agent.displayName).font(NotchTokens.Typography.bodyEmphasis).lineLimit(1)
                    Text("\(session.project) · \(place)").font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(OrbitTeamPolicy.status(working: session.isWorking, waiting: session.isWaiting,
                                            since: session.turnStartedAt ?? session.updatedAt, now: Date()))
                    .font(NotchTokens.Typography.caption)
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }
            if let prompt = session.lastPrompt, !prompt.isEmpty {
                Text(prompt).font(NotchTokens.Typography.body).lineLimit(2)
            }
            Text(activity).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                NotchPillButton(title: session.agent.readsTranscripts ? "Open" : "Show window", symbol: "arrow.up.right") { onOpen() }
                if session.appBundleID == Bundle.main.bundleIdentifier {
                    // Started from a Start icon: it runs in the notch's Terminal tab.
                    NotchPillButton(title: "Terminal", symbol: "apple.terminal") {
                        DynamicIslandViewCoordinator.shared.currentView = .terminal
                    }
                }
                if !session.isWorking && !session.isWaiting {
                    NotchPillButton(title: "Dismiss", symbol: "xmark") { hub.dismiss(session) }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: NotchTokens.Radius.card, style: .continuous)
            .strokeBorder(session.isWaiting ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1))
    }

    private var statusTint: Color {
        session.isWaiting ? .orange : session.isWorking ? .green : .secondary
    }

    private var activity: String {
        switch session.state {
        case .ready: return "Ready"
        case .working(let activity): return activity
        case .waiting(let reason): return "Needs you · \(reason)"
        case .done(let summary): return "Done · \(summary)"
        }
    }

    /// Where it runs: a background copy, the notch's terminal, or an app.
    private var place: String {
        if session.cwd.hasPrefix(OrbitJobs.worktrees.path) { return "background copy" }
        guard let bundle = session.appBundleID else { return "terminal" }
        if bundle == Bundle.main.bundleIdentifier { return "NotchFlow" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return "terminal"
    }
}
