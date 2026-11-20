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
                HStack(alignment: .top, spacing: NotchTokens.Spacing.m) {
                    AgentSessionList(composing: $composing, panelSizeValue: $panelSizeValue)
                        .frame(width: panelSize.listWidth)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                    Group {
                        if composing {
                            AgentTaskComposer { withAnimation(NotchTokens.Motion.standard) { composing = false } }
                        } else if let selected = conversations.selected {
                            AgentChatView(summary: selected, textScale: panelSize.textScale)
                        } else {
                            NotchEmptyState(symbol: "sparkles",
                                            title: hub.sessions.isEmpty && conversations.recent.isEmpty ? "No sessions yet" : "Pick a session",
                                            detail: AgentSetup.anyAgentConnected
                                                ? "Pick one on the left to see its conversation and keep it going, or start a New task."
                                                : "Connect Claude Code or Codex in Settings > AI Agents, then start a New task here.")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .notchTabPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: hub.requests.isEmpty) { _, _ in updateSuppression() }
        .onChange(of: composing) { _, _ in updateSuppression() }
        .onAppear {
            conversations.refreshList(force: true)
            if let selected = conversations.selected { conversations.select(selected) }
            updateSuppression()
        }
        .onDisappear {
            conversations.stopFollowing()
            vm.setAutoCloseSuppression(false, token: interactionToken)
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

// MARK: - Session list

private struct AgentSessionList: View {
    @Binding var composing: Bool
    @Binding var panelSizeValue: Int
    private var panelSize: AgentPanelSize { AgentPanelSize(rawValue: panelSizeValue) ?? .regular }
    @ObservedObject private var hub = AgentHub.shared
    @ObservedObject private var conversations = AgentConversations.shared

    private var recentOnly: [AgentSessionSummary] {
        let live = Set(hub.sessions.map(\.id))
        return conversations.recent.filter { !live.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            HStack(spacing: NotchTokens.Spacing.s) {
                Text("AI Agents").font(NotchTokens.Typography.title)
                Spacer(minLength: 0)
                sizeMenu
                NotchPillButton(title: "New", symbol: "plus", prominent: !composing) {
                    withAnimation(NotchTokens.Motion.standard) { composing.toggle() }
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if conversations.startingNewSession {
                        AgentListRow(symbol: "sparkle", title: "Starting…", subtitle: "New session", tint: .white,
                                     busy: true, selected: false) {}
                    }
                    if !hub.sessions.isEmpty {
                        NotchSectionHeader(title: "Live")
                        ForEach(hub.sessions) { session in
                            AgentListRow(symbol: session.agent.symbol, title: session.project, subtitle: liveSubtitle(session),
                                         tint: tint(session.state), busy: session.isWorking || conversations.isRunning(session.id),
                                         selected: conversations.selected?.id == session.id) {
                                composing = false
                                if session.agent == .claudeCode || session.agent == .codex {
                                    conversations.select(sessionID: session.id)
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
                    if hub.sessions.isEmpty && recentOnly.isEmpty && !conversations.startingNewSession {
                        Text("Claude Code and Codex sessions from the last two weeks appear here.")
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
