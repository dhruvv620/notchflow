// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI

struct CallIslandView: View {
    let call: CommunicationCall
    var compact = false
    @ObservedObject private var manager = CommunicationsManager.shared
    @Default(.communicationShowPreviews) private var showPreviews
    @State private var photo: NSImage?
    @State private var isComposing = false
    @State private var customMessage = ""
    @State private var isSendingMessage = false
    @FocusState private var composeFocused: Bool
    private var busy: Bool { manager.pendingCallActionIDs.contains(call.id) }

    var body: some View {
        Group {
            if compact { compactContent }
            else { expandedContent }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(call.app.title) \(phaseLabel)")
    }

    private var compactContent: some View {
        HStack(spacing: 9) {
            sourceIcon(size: 25)
            VStack(alignment: .leading, spacing: 1) {
                Text(callerLabel).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(call.app.title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 5)
            if call.phase == .active { duration.font(.system(size: 10, weight: .medium)) }
            if call.phase == .incoming {
                if call.actions.contains(.decline) { callButton(.decline, symbol: "phone.down.fill", label: "Decline", color: .red, iconOnly: true) }
                if call.actions.contains(.answer) { callButton(.answer, symbol: "phone.fill", label: "Answer", color: .green, iconOnly: true) }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CallerAvatar(name: call.caller, photo: photo, size: 48, ringing: call.phase == .incoming)
                VStack(alignment: .leading, spacing: 3) {
                    Text(callerLabel).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: call.app.symbol)
                        Text("\(call.app.title) · \(phaseLabel)")
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    if showPreviews, let reason = manager.recentMessage(from: call.caller) {
                        Label(reason.body, systemImage: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(2)
                            .help("Their latest message")
                    }
                }
                Spacer(minLength: 5)
                if call.phase == .active { duration.font(.system(size: 13, weight: .medium)) }
            }

            if isComposing {
                NotchComposeField(
                    placeholder: "Message to \(callerLabel)",
                    text: $customMessage,
                    isSending: isSendingMessage,
                    onSend: { decline(with: customMessage) },
                    onCancel: { isComposing = false; customMessage = "" },
                    isFocused: $composeFocused
                )
                .onAppear { composeFocused = true }
            } else {
                HStack(spacing: 8) {
                    if call.actions.contains(.decline) { callButton(.decline, symbol: "phone.down.fill", label: "Decline", color: .red) }
                    if call.phase == .incoming {
                        Menu {
                            ForEach(CallReplyPolicy.presets, id: \.self) { preset in
                                Button(preset) { decline(with: preset) }
                            }
                            Divider()
                            Button("Custom Message…") { isComposing = true }
                        } label: {
                            Label("Message", systemImage: "text.bubble.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .help("Decline and send a message")
                        .disabled(busy || isSendingMessage)
                    }
                    if call.actions.contains(.answer) { callButton(.answer, symbol: "phone.fill", label: "Answer", color: .green) }
                    if call.actions.contains(.unmute) {
                        callButton(.unmute, symbol: "mic.slash.fill", label: "Unmute", color: .accentColor)
                    } else if call.actions.contains(.mute) {
                        callButton(.mute, symbol: "mic.fill", label: "Mute", color: .accentColor)
                    }
                    if call.actions.contains(.toggleVideo) { callButton(.toggleVideo, symbol: "video.fill", label: "Video", color: .accentColor) }
                    if call.actions.contains(.end) { callButton(.end, symbol: "phone.down.fill", label: "End", color: .red) }
                    Spacer(minLength: 0)
                    Button("Open app", systemImage: "arrow.up.right") {
                        if call.actions.contains(.open) { perform(.open) }
                        else { manager.openSource(call.app) }
                    }.font(.system(size: 11)).buttonStyle(.plain).disabled(busy)
                    if busy || isSendingMessage { ProgressView().controlSize(.mini) }
                }
            }
            if let error = manager.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: call.caller) {
            guard showPreviews, !call.caller.isEmpty,
                  let data = await ContactDirectory.shared.lookup(name: call.caller)?.photo else { return }
            photo = NSImage(data: data)
        }
    }

    private func decline(with message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingMessage else { return }
        isSendingMessage = true
        Task {
            let sent = await manager.declineWithMessage(text, callID: call.id)
            isSendingMessage = false
            if sent { isComposing = false; customMessage = "" }
        }
    }

    private var callerLabel: String { showPreviews ? (call.caller.isEmpty ? call.app.title : call.caller) : "Call" }
    private var phaseLabel: String {
        switch call.phase {
        case .incoming: return "Incoming call"
        case .connecting: return "Connecting…"
        case .active: return "In call"
        }
    }
    private func sourceIcon(size: CGFloat) -> some View {
        Image(systemName: call.app.symbol).font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(call.phase == .incoming ? Color.green : Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.08), in: Circle())
    }
    private var duration: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 1) {
                Text(elapsed(at: context.date)).monospacedDigit()
                if call.connectedAt == nil {
                    Text("Detected").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .help(call.connectedAt == nil ? "Time since this call was first detected; its connection time was not provided." : "Call duration")
    }
    private func elapsed(at date: Date) -> String {
        let interval = date.timeIntervalSince(call.connectedAt ?? call.observedAt)
        let seconds = interval.isFinite ? Int(min(max(0, interval), 31_536_000)) : 0
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private func callButton(_ action: CommunicationCallAction, symbol: String, label: String, color: Color, iconOnly: Bool = false) -> some View {
        Button { perform(action) } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if !iconOnly { Text(label) }
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, iconOnly ? 7 : 10).padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
        }.buttonStyle(.plain).disabled(busy).accessibilityLabel(label).help(label)
    }
    private func perform(_ action: CommunicationCallAction) {
        guard !busy else { return }
        Task { await manager.performCall(action, id: call.id) }
    }
}

/// A caller's photo, or their initials on a color of their own.
struct CallerAvatar: View {
    let name: String
    let photo: NSImage?
    var size: CGFloat = 44
    var ringing = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if let photo {
                Image(nsImage: photo).resizable().scaledToFill()
            } else {
                let hue = CallReplyPolicy.hue(for: name)
                LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.8),
                                        Color(hue: hue, saturation: 0.7, brightness: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(CallReplyPolicy.initials(for: name))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .background {
            if ringing {
                Circle()
                    .stroke(Color.green.opacity(pulse ? 0 : 0.6), lineWidth: 3)
                    .scaleEffect(pulse ? 1.35 : 1)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }
        }
        .accessibilityHidden(true)
    }
}

