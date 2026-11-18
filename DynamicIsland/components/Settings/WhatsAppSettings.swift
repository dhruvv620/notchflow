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

import AppKit
import Defaults
import SwiftUI

struct WhatsAppSettings: View {
    @ObservedObject private var manager = WhatsAppManager.shared
    @Default(.enableWhatsAppFeature) private var enableWhatsAppFeature
    @Default(.whatsAppShowIncomingMessages) private var showIncomingMessages
    @Default(.whatsAppIgnoredChats) private var ignoredChats
    @Default(.whatsAppIgnoredChatNames) private var ignoredChatNames
    @State private var confirmUnlink = false
    @State private var confirmRemove = false

    private func highlightID(_ title: String) -> String {
        "whatsapp-\(title)"
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableWhatsAppFeature) {
                    Text("Show my WhatsApp messages")
                }
                .settingsHighlight(id: highlightID("Show my WhatsApp messages"))
            } header: {
                Text("WhatsApp (experimental)")
            } footer: {
                Text("Unofficial integration: it goes through GOWA, an open-source WhatsApp gateway NotchFlow runs on this Mac. Use it with your own account only. WhatsApp may restrict accounts that misuse it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if enableWhatsAppFeature {
                gatewaySection
                accountSection

                if manager.state.isLinked {
                    notificationSection
                    readingSection
                    ignoredSection
                }

                advancedSection
            }
        }
        .onAppear {
            if enableWhatsAppFeature && manager.latestVersion == nil {
                Task { await manager.checkForUpdate() }
            }
        }
        .onDisappear {
            manager.cancelLinking()
        }
    }

    // MARK: Gateway

    private var gatewaySection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: gatewayIcon.name)
                    .foregroundStyle(gatewayIcon.color)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(gatewayTitle)
                    if let detail = gatewayDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                gatewayButton
            }

            if case .installing(let progress) = manager.state {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }

            if let error = manager.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Gateway")
        } footer: {
            Text("The gateway is downloaded from GitHub (aldinokemal/go-whatsapp-web-multidevice), checked against its published checksum, and only listens on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gatewayIcon: (name: String, color: Color) {
        switch manager.state {
        case .notInstalled: return ("arrow.down.circle", .secondary)
        case .installing, .starting: return ("hourglass", .secondary)
        case .failed: return ("xmark.octagon.fill", .red)
        default: return ("checkmark.circle.fill", .green)
        }
    }

    private var gatewayTitle: String {
        switch manager.state {
        case .notInstalled:
            return String(localized: "Gateway not installed")
        case .installing:
            return String(localized: "Installing gateway…")
        case .starting:
            return String(localized: "Starting gateway…")
        case .failed:
            return String(localized: "Gateway stopped")
        default:
            let version = manager.installedVersion.isEmpty ? "" : " \(manager.installedVersion)"
            return String(localized: "Gateway GOWA\(version) running")
        }
    }

    private var gatewayDetail: String? {
        if manager.hasUpdate, let latest = manager.latestVersion {
            return String(localized: "Version \(latest) is available.")
        }
        if case .notInstalled = manager.state {
            return String(localized: "About 30 MB. Needed to connect to WhatsApp.")
        }
        return nil
    }

    @ViewBuilder
    private var gatewayButton: some View {
        switch manager.state {
        case .notInstalled:
            Button("Install") {
                Task { await manager.installOrUpdateGateway() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.whatsAppGreen)
        case .installing, .starting:
            ProgressView().controlSize(.small)
        case .failed:
            HStack {
                Button("Restart") { manager.restartGateway() }
                Button("Reinstall") {
                    Task { await manager.installOrUpdateGateway() }
                }
            }
        default:
            if manager.hasUpdate {
                Button("Update") {
                    Task { await manager.installOrUpdateGateway() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.whatsAppGreen)
            } else {
                Button(manager.isCheckingForUpdate ? "Checking…" : "Check for Updates") {
                    Task { await manager.checkForUpdate() }
                }
                .disabled(manager.isCheckingForUpdate)
            }
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountSection: some View {
        switch manager.state {
        case .connected, .reconnecting:
            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(manager.state.isConnected ? Color.whatsAppGreen : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(manager.state.isConnected
                         ? String(localized: "Connected as \(manager.accountPhone)")
                         : String(localized: "Reconnecting as \(manager.accountPhone)…"))
                    Spacer()
                    Button("Unlink", role: .destructive) {
                        confirmUnlink = true
                    }
                }
                Text(manager.receivesLiveUpdates
                     ? "Live: new messages arrive at once."
                     : "New messages arrive within a minute until the first live update comes in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Account")
            }
            .confirmationDialog("Unlink WhatsApp from NotchFlow?", isPresented: $confirmUnlink) {
                Button("Unlink", role: .destructive) {
                    Task { await manager.unlink() }
                }
            } message: {
                Text("NotchFlow is removed from your phone's linked devices. You can link it again by scanning a new QR code.")
            }
        case .waitingForLink:
            Section {
                linkingView
            } header: {
                Text("Link your account")
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var linkingView: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                if let image = manager.qrImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(8)
                } else if manager.isLinking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 48))
                        .foregroundStyle(.black.opacity(0.25))
                }
            }
            .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 8) {
                Text("Scan with your phone")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Open WhatsApp on your phone.")
                    Text("2. Go to Settings › Linked devices.")
                    Text("3. Tap Link a device and point the camera at this code.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if manager.isLinking {
                    if let expiry = manager.qrExpiresAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, Int(expiry.timeIntervalSince(context.date)))
                            Text("A new code appears in \(remaining)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Cancel") { manager.cancelLinking() }
                } else {
                    Button("Show QR Code") { manager.beginLinking() }
                        .buttonStyle(.borderedProminent)
                        .tint(.whatsAppGreen)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: Options

    private var notificationSection: some View {
        Section {
            Defaults.Toggle(key: .whatsAppShowIncomingMessages) {
                Text("Show new messages in the notch")
            }
            if showIncomingMessages {
                Defaults.Toggle(key: .whatsAppShowMessagePreviews) {
                    Text("Show message text")
                }
                Defaults.Toggle(key: .whatsAppMuteGroups) {
                    Text("Mute groups (unless I'm mentioned)")
                }
                .settingsHighlight(id: highlightID("Mute groups"))
                Defaults.Toggle(key: .whatsAppQuietDuringFocus) {
                    Text("Stay quiet during a Focus")
                }
            }
        } header: {
            Text("New messages")
        }
    }

    private var readingSection: some View {
        Section {
            Defaults.Toggle(key: .whatsAppMarkReadOnOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mark as read when I open a conversation")
                    Text("Off: marked read only when you reply. Never when a message just arrives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Mark as read when I open a conversation"))
        } header: {
            Text("Read receipts")
        }
    }

    private var ignoredSection: some View {
        Section {
            if ignoredChats.isEmpty {
                Text("Right-click a chat in the notch and choose Ignore This Chat to hide it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ignoredChats, id: \.self) { chatID in
                    HStack {
                        Text(ignoredChatNames[chatID] ?? WhatsAppJID.displayNumber(chatID))
                        Spacer()
                        Button("Stop Ignoring") {
                            manager.setIgnored(false, chatID: chatID)
                        }
                    }
                }
            }
        } header: {
            Text("Ignored chats")
        } footer: {
            Text("Ignored chats are hidden from the notch and never announced.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedSection: some View {
        Section {
            HStack {
                Button("Show Gateway Files in Finder") {
                    let url = WhatsAppGatewayInstaller.rootDirectory
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Spacer()
                Button("Remove Gateway…", role: .destructive) {
                    confirmRemove = true
                }
                .disabled(!WhatsAppGatewayInstaller.isInstalled)
            }
        } header: {
            Text("Advanced")
        }
        .confirmationDialog("Remove the WhatsApp gateway?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                Task { await manager.removeGateway() }
            }
        } message: {
            Text("This unlinks your account and deletes the gateway with its local copy of your chats.")
        }
    }
}
