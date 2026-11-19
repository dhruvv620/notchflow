// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import SwiftUI

/// Promises you made and promises made to you, from your chats.
struct PromisesList: View {
    @ObservedObject private var keeper = PromiseKeeper.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var followingUp: UUID?
    @State private var draft = ""
    @State private var sending = false
    @State private var lastResult: String?
    @State private var interactionToken = UUID()
    @FocusState private var draftFocused: Bool

    var body: some View {
        if keeper.open.isEmpty {
            NotchEmptyState(symbol: "hand.raised",
                            title: "No open promises",
                            detail: "When you write \u{201C}I'll send it tonight\u{201D} in WhatsApp or a reply from the notch, it shows up here, and the notch reminds you before it's due.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if !keeper.mine.isEmpty {
                        NotchSectionHeader(title: "You promised")
                        ForEach(keeper.mine) { row($0) }
                    }
                    if !keeper.theirs.isEmpty {
                        NotchSectionHeader(title: "Waiting on others")
                        ForEach(keeper.theirs) { row($0) }
                    }
                    if let lastResult {
                        Text(lastResult).font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 1)
            }
            .onHover { vm.setScrollGestureSuppression($0, token: interactionToken) }
            .onChange(of: followingUp) { _, id in vm.setAutoCloseSuppression(id != nil, token: interactionToken) }
            .onDisappear {
                vm.setScrollGestureSuppression(false, token: interactionToken)
                vm.setAutoCloseSuppression(false, token: interactionToken)
            }
        }
    }

    private func row(_ promise: TrackedPromise) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: promise.kind == .mine ? "hand.raised.fill" : "hourglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(promise.isOverdue ? Color.red : appearance.accentColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.headline(promise))
                        .font(NotchTokens.Typography.bodyEmphasis)
                        .lineLimit(1)
                    Text("\(promise.person) · \(promise.sourceName) · \(Self.dueText(promise))")
                        .font(NotchTokens.Typography.caption)
                        .foregroundStyle(promise.isOverdue ? Color.red.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }
                .help(promise.quote)
                Spacer(minLength: 4)
                NotchIconButton(symbol: "checkmark", help: promise.kind == .mine ? "Done" : "Received") { keeper.markDone(promise.id) }
                NotchIconButton(symbol: "arrowshape.turn.up.left", help: promise.kind == .mine ? "Tell them you're running late" : "Send a polite reminder") {
                    if followingUp == promise.id { followingUp = nil } else {
                        draft = keeper.draft(for: promise)
                        followingUp = promise.id
                        draftFocused = true
                    }
                }
                Menu {
                    Button("Snooze until tomorrow") { keeper.snooze(promise.id) }
                    Button("Snooze an hour") { keeper.snooze(promise.id, by: 3600) }
                    Divider()
                    Button("Not a promise", role: .destructive) { keeper.dismiss(promise.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(.secondary)
            }
            if followingUp == promise.id {
                NotchComposeField(placeholder: "Message \(promise.person)", text: $draft, isSending: sending,
                                  isEnabled: true, onSend: { send(promise) }, onCancel: { followingUp = nil },
                                  isFocused: $draftFocused)
                if !keeper.canSendFollowUp(promise) {
                    Text("This chat can't be reached from the notch; Send copies the message so you can paste it.")
                        .font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func send(_ promise: TrackedPromise) {
        sending = true
        Task {
            let sent = await keeper.sendFollowUp(draft, for: promise)
            sending = false
            if sent {
                followingUp = nil
                lastResult = keeper.canSendFollowUp(promise) ? "Sent to \(promise.person)." : "Copied. Paste it in your chat with \(promise.person)."
                if promise.kind == .mine { keeper.snooze(promise.id) }
            } else {
                lastResult = "Couldn't send. Open the chat and paste it instead."
            }
        }
    }

    /// Your promise as it reads ("Send Sam the deck"), theirs with who made it
    /// ("Alex: send me the invoice").
    static func headline(_ promise: TrackedPromise) -> String {
        guard promise.kind == .theirs else { return promise.title }
        let first = PromisePolicy.firstName(promise.person)
        let who = first.isEmpty ? promise.person : first
        let what = promise.title.prefix(1).lowercased() + promise.title.dropFirst()
        return "\(who): \(what)"
    }

    /// "due tonight 8:00 PM", "due tomorrow 10:00 AM", "due Fri 5:00 PM", "overdue".
    static func dueText(_ promise: TrackedPromise, now: Date = Date()) -> String {
        if promise.isOverdue { return "overdue" }
        let calendar = Calendar.current
        let time = promise.due.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(promise.due) {
            return calendar.component(.hour, from: promise.due) >= 18 ? "due tonight \(time)" : "due today \(time)"
        }
        if calendar.isDateInTomorrow(promise.due) { return "due tomorrow \(time)" }
        return "due \(promise.due.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// Under the closed notch, an hour before a promise is due.
struct PromiseNudgeActivity: View {
    @ObservedObject private var keeper = PromiseKeeper.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    let isHovering: Bool

    private static func who(_ promise: TrackedPromise?) -> String {
        guard let promise else { return "" }
        let first = PromisePolicy.firstName(promise.person)
        return first.isEmpty ? promise.person : first
    }

    var body: some View {
        let promise = keeper.nudge
        ClosedNotchWings(isHovering: isHovering) {
            Image(systemName: promise?.kind == .theirs ? "hourglass" : "hand.raised.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
            Text(Self.who(promise))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        } trailing: {
            Text(promise.map { PromisesList.dueText($0).replacingOccurrences(of: "due ", with: "") } ?? "")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
                .lineLimit(1)
        }
        .help(promise.map { ($0.kind == .mine ? "You told \($0.person): " : "\($0.person) promised: ") + $0.title } ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(promise.map { ($0.kind == .mine ? "You promised \($0.person): " : "\($0.person) promised you: ") + $0.title } ?? "")
    }
}
