// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI
import UniformTypeIdentifiers

extension Defaults.Keys {
    /// WhatsApp chats pinned to the Shelf corner, in order (at most five).
    static let peoplePins = Key<[String]>("peoplePins", default: [])
}

enum PeoplePins {
    static let limit = 5

    static func isPinned(_ chatID: String) -> Bool { Defaults[.peoplePins].contains(chatID) }

    static func toggle(_ chatID: String) {
        var pins = Defaults[.peoplePins]
        if let index = pins.firstIndex(of: chatID) {
            pins.remove(at: index)
        } else {
            guard pins.count < limit else { return }
            pins.append(chatID)
        }
        Defaults[.peoplePins] = pins
    }
}

/// Faces in the Shelf corner: drop a file on one to send it on WhatsApp.
struct ShelfPeoplePins: View {
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @Default(.peoplePins) private var pins
    @Default(.enableWhatsAppFeature) private var whatsAppEnabled

    var body: some View {
        if whatsAppEnabled, whatsApp.state.isLinked, !pins.isEmpty {
            HStack(spacing: 4) {
                ForEach(pins, id: \.self) { chatID in
                    PeoplePinFace(chatID: chatID)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
        }
    }
}

private struct PeoplePinFace: View {
    let chatID: String
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @State private var isTargeted = false
    @State private var status: Status = .idle

    private enum Status { case idle, sending, sent, failed }

    private var chat: WhatsAppChat? { whatsApp.chat(id: chatID) }
    private var name: String { chat?.displayName ?? WhatsAppJID.displayNumber(chatID) }

    var body: some View {
        ZStack {
            WhatsAppAvatar(initial: chat?.initial ?? "#", isGroup: WhatsAppJID.isGroup(chatID), size: 24)
                .scaleEffect(isTargeted ? 1.25 : 1)
            switch status {
            case .idle: EmptyView()
            case .sending: ProgressView().controlSize(.mini)
            case .sent: badge("checkmark", .green)
            case .failed: badge("exclamationmark", .red)
            }
        }
        .overlay(Circle().strokeBorder(Color.whatsAppGreen, lineWidth: isTargeted ? 2 : 0))
        .animation(.snappy(duration: 0.18), value: isTargeted)
        .help(whatsApp.lastSendError.flatMap { status == .failed ? $0 : nil } ?? "Drop files to send to \(name) on WhatsApp")
        .onTapGesture {
            DynamicIslandViewCoordinator.shared.currentView = .whatsapp
            whatsApp.openChat(chatID)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { @MainActor in await send(providers) }
            return true
        }
        .contextMenu {
            Button("Unpin \(name)") { PeoplePins.toggle(chatID) }
        }
        .accessibilityLabel("Send files to \(name)")
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 12, height: 12)
            .background(Circle().fill(color))
            .offset(x: 9, y: 9)
    }

    @MainActor
    private func send(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await Self.loadURL(provider) { urls.append(url) }
        }
        guard !urls.isEmpty else { return }
        status = .sending
        let ok = await whatsApp.sendFiles(urls, to: chatID)
        status = ok ? .sent : .failed
        try? await Task.sleep(nanoseconds: ok ? 1_800_000_000 : 4_000_000_000)
        status = .idle
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }
}
