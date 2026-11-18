/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import SwiftUI

extension Color {
    /// WhatsApp's brand green (#25D366).
    static let whatsAppGreen = Color(red: 0.145, green: 0.827, blue: 0.4)
}

/// The WhatsApp tab: chats on the left, the open conversation and a reply
/// field on the right.
struct NotchWhatsAppView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = WhatsAppManager.shared

    var body: some View {
        Group {
            switch manager.state {
            case .connected, .reconnecting:
                if manager.chats.isEmpty && manager.isRefreshingChats {
                    WhatsAppPlaceholder(icon: "message.fill", title: "Loading chats…", showsProgress: true)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        WhatsAppChatListColumn()
                            .frame(width: 228)
                        WhatsAppConversationColumn()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            case .disabled:
                WhatsAppPlaceholder(icon: "message.fill", title: "WhatsApp is turned off", subtitle: "Turn it on in Settings › WhatsApp.", action: openSettings)
            case .notInstalled:
                WhatsAppPlaceholder(icon: "arrow.down.circle", title: "Gateway not installed", subtitle: "Install it from Settings › WhatsApp, then scan the QR code.", action: openSettings)
            case .installing:
                WhatsAppPlaceholder(icon: "arrow.down.circle", title: "Installing the gateway…", showsProgress: true)
            case .starting:
                WhatsAppPlaceholder(icon: "message.fill", title: "Starting WhatsApp…", showsProgress: true)
            case .waitingForLink:
                WhatsAppPlaceholder(icon: "qrcode", title: "Link your WhatsApp", subtitle: "Open Settings › WhatsApp and scan the QR code with your phone.", action: openSettings)
            case .failed(let message):
                WhatsAppPlaceholder(icon: "exclamationmark.triangle", title: "WhatsApp is unavailable", subtitle: message, action: openSettings)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onAppear {
            manager.isTabVisible = true
            manager.dismissBanner()
            Task {
                await manager.refreshChats()
                if let selected = manager.selectedChatID {
                    await manager.loadMessages(selected)
                    if Defaults[.whatsAppMarkReadOnOpen] {
                        await manager.markChatRead(selected)
                    }
                }
            }
        }
        .onDisappear {
            manager.isTabVisible = false
        }
    }

    private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }
}

// MARK: - Chat list

private struct WhatsAppChatListColumn: View {
    @ObservedObject private var manager = WhatsAppManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(manager.state.isConnected ? Color.whatsAppGreen : Color.orange)
                    .frame(width: 7, height: 7)
                Text("WhatsApp")
                    .font(.system(size: 13, weight: .semibold))
                if manager.totalUnread > 0 {
                    Text("\(manager.totalUnread) unread")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.whatsAppGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.whatsAppGreen.opacity(0.16), in: Capsule())
                }
                Spacer(minLength: 0)
                Button {
                    Task { await manager.refreshChats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(manager.isRefreshingChats ? 360 : 0))
                        .animation(manager.isRefreshingChats ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : Animation.default, value: manager.isRefreshingChats)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh")
            }
            .padding(.horizontal, 4)

            if case .reconnecting = manager.state {
                Text("Reconnecting…")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }

            if manager.visibleChats.isEmpty {
                Spacer()
                Text("No chats yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(manager.visibleChats) { chat in
                            WhatsAppChatRow(chat: chat, isSelected: manager.selectedChatID == chat.id) {
                                manager.openChat(chat.id)
                            }
                            .contextMenu {
                                Button("Mark as Read") {
                                    Task { await manager.markChatRead(chat.id) }
                                }
                                Button("Add to Todos") {
                                    Task { await RemindersManager.shared.capture(TodoCapturePolicy.followUpTitle(sender: chat.displayName, body: chat.preview ?? "")) }
                                }
                                Button("Ignore This Chat") {
                                    manager.setIgnored(true, chatID: chat.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct WhatsAppChatRow: View {
    let chat: WhatsAppChat
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                WhatsAppAvatar(initial: chat.initial, isGroup: chat.isGroup, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(chat.displayName)
                            .font(.system(size: 12, weight: chat.unreadCount > 0 ? .semibold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let time = chat.lastMessageTime {
                            Text(WhatsAppTimeFormatter.short(time))
                                .font(.system(size: 10))
                                .foregroundStyle(chat.unreadCount > 0 ? Color.whatsAppGreen : .secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(previewText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if chat.unreadCount > 0 {
                            Text("\(chat.unreadCount)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.whatsAppGreen, in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.14 : (isHovering ? 0.08 : 0.05)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var previewText: String {
        guard let preview = chat.preview else { return "" }
        if chat.previewIsFromMe { return String(localized: "You: \(preview)") }
        if let sender = chat.previewSender, !sender.isEmpty { return "\(sender): \(preview)" }
        return preview
    }
}

struct WhatsAppAvatar: View {
    let initial: String
    let isGroup: Bool
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.whatsAppGreen.opacity(0.22))
            if isGroup {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color.whatsAppGreen)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Color.whatsAppGreen)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Conversation

private struct WhatsAppConversationColumn: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = WhatsAppManager.shared
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var isReplyFocused: Bool
    @State private var autoCloseToken = UUID()

    var body: some View {
        Group {
            if let chatID = manager.selectedChatID, let chat = manager.chat(id: chatID) {
                VStack(spacing: 6) {
                    header(for: chat)
                    messageList(for: chat)
                    replyBar(for: chat)
                }
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: chatID) { _, _ in
                    draft = ""
                    isReplyFocused = false
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.whatsAppGreen.opacity(0.8))
                    Text(manager.totalUnread > 0 ? "\(manager.totalUnread) unread messages" : "You're all caught up")
                        .font(.system(size: 12, weight: .medium))
                    Text("Pick a chat to read and reply.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onChange(of: isReplyFocused) { _, focused in
            // Keep the notch open while a reply is being typed.
            vm.setAutoCloseSuppression(focused, token: autoCloseToken)
        }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
        }
    }

    private func header(for chat: WhatsAppChat) -> some View {
        HStack(spacing: 8) {
            Button {
                isReplyFocused = false
                manager.closeChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back")

            WhatsAppAvatar(initial: chat.initial, isGroup: chat.isGroup, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !chat.isGroup, chat.displayName != WhatsAppJID.displayNumber(chat.id) {
                    Text(WhatsAppJID.displayNumber(chat.id))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if manager.loadingChatIDs.contains(chat.id) {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func messageList(for chat: WhatsAppChat) -> some View {
        let list = manager.messages[chat.id] ?? []
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? list[index - 1] : nil
                        let showsSender = chat.isGroup && !message.isFromMe
                            && (previous == nil || previous?.senderJID != message.senderJID || previous?.isFromMe == true)
                        WhatsAppMessageBubble(message: message, showsSender: showsSender)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
            .onAppear {
                if let last = list.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: list.last?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
    }

    private func replyBar(for chat: WhatsAppChat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let error = manager.lastSendError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            NotchComposeField(
                placeholder: "Reply to \(chat.displayName)",
                text: $draft,
                isSending: isSending,
                isEnabled: manager.state.isConnected,
                onSend: { send(to: chat.id) },
                isFocused: $isReplyFocused
            )
        }
    }

    private var canSend: Bool {
        !isSending && manager.state.isConnected && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(to chatID: String) {
        guard canSend else { return }
        let text = draft
        draft = ""
        isSending = true
        Task {
            let sent = await manager.send(text, to: chatID)
            isSending = false
            if !sent && draft.isEmpty {
                // Give the text back so it is not lost.
                draft = text
            }
            isReplyFocused = true
        }
    }
}

private struct WhatsAppMessageBubble: View {
    let message: WhatsAppMessage
    let showsSender: Bool

    var body: some View {
        HStack {
            if message.isFromMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                if showsSender {
                    Text(message.senderName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.whatsAppGreen)
                        .lineLimit(1)
                }
                Text(message.previewText)
                    .font(.system(size: 12))
                    .italic(message.isRevoked)
                    .foregroundStyle(message.isRevoked ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 3) {
                    if message.isEdited {
                        Text("Edited")
                    }
                    Text(WhatsAppTimeFormatter.clock(message.timestamp))
                    if message.isFromMe {
                        Image(systemName: message.isPending ? "clock" : "checkmark")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(message.isFromMe ? Color.whatsAppGreen.opacity(0.28) : Color.white.opacity(0.1))
            )
            .fixedSize(horizontal: false, vertical: true)
            if !message.isFromMe { Spacer(minLength: 40) }
        }
        .opacity(message.isPending ? 0.7 : 1)
    }
}

// MARK: - Placeholder

private struct WhatsAppPlaceholder: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var showsProgress = false
    var action: (() -> Void)? = nil

    var body: some View {
        NotchEmptyState(symbol: icon, title: title, detail: subtitle, showsProgress: showsProgress) {
            if let action {
                NotchPillButton(title: "Open Settings", symbol: "gear", prominent: true, action: action)
            }
        }
    }
}
