/*
 * NotchFlow
 * Copyright (C) 2026 dhruvv620
 * Portions Copyright (C) 2024-2026 Atoll Contributors
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
    @Default(.whatsAppAccountNames) private var accountNames
    @State private var unlinkSlot: WhatsAppAccountSlot?
    @State private var confirmRemove = false

    private func highlightID(_ title: String) -> String {
        "whatsapp-\(title)"
    }

    var body: some View {
        Form {
            if !enableWhatsAppFeature {
                Section {
                    Text("Off: nothing runs and nothing connects to WhatsApp.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
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
                        .foregroundStyle(SettingsPalette.warn)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Experimental and unofficial: NotchFlow runs GOWA, an open-source WhatsApp helper, on this Mac only. Use your own account. WhatsApp may limit accounts that misuse it.")
        }
    }

    private var gatewayIcon: (name: String, color: Color) {
        switch manager.state {
        case .notInstalled: return ("arrow.down.circle", SettingsPalette.warn)
        case .installing, .starting: return ("hourglass", .secondary)
        case .failed: return ("xmark.octagon.fill", SettingsPalette.danger)
        default: return ("checkmark.circle.fill", SettingsPalette.ok)
        }
    }

    private var gatewayTitle: String {
        switch manager.state {
        case .notInstalled:
            return String(localized: "Not set up yet")
        case .installing:
            return String(localized: "Setting up…")
        case .starting:
            return String(localized: "Starting…")
        case .failed:
            return String(localized: "Stopped")
        default:
            let version = manager.installedVersion.isEmpty ? "" : " \(manager.installedVersion)"
            return String(localized: "Running (GOWA\(version))")
        }
    }

    private var gatewayDetail: String? {
        if manager.hasUpdate, let latest = manager.latestVersion {
            return String(localized: "Version \(latest) is available.")
        }
        if case .notInstalled = manager.state {
            return String(localized: "A 30 MB download that connects NotchFlow to WhatsApp.")
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
            .settingsPrimaryButton()
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
                .settingsPrimaryButton()
            } else {
                Button(manager.isCheckingForUpdate ? "Checking…" : "Check for Updates") {
                    Task { await manager.checkForUpdate() }
                }
                .disabled(manager.isCheckingForUpdate)
            }
        }
    }

    // MARK: Accounts

    @ViewBuilder
    private var accountSection: some View {
        if manager.state.isLinked || manager.state == .waitingForLink {
            Section {
                ForEach(manager.activeSlots, id: \.self) { slot in
                    accountRow(slot)
                }
                if manager.activeSlots.count == 1, manager.linkState(for: .primary).isLinked {
                    HStack {
                        SettingsRowLabel(title: "Another account",
                                         detail: "Link a second WhatsApp, like personal next to business.")
                        Spacer()
                        Button("Add Account") {
                            Task { await manager.addSecondAccount() }
                        }
                        .disabled(manager.isLinking)
                    }
                    .settingsHighlight(id: highlightID("Another account"))
                }
                if manager.state.isLinked {
                    SettingsStatus(text: manager.receivesLiveUpdates
                                   ? "Live: new messages arrive at once."
                                   : "New messages arrive within a minute until live updates start.",
                                   kind: manager.receivesLiveUpdates ? .ok : .neutral)
                }
            } header: {
                Text(manager.activeSlots.count > 1 ? "Accounts" : "Account")
            } footer: {
                if manager.activeSlots.count > 1 {
                    Text("Each account is a linked device on its phone, like WhatsApp Web.")
                }
            }
            .confirmationDialog("Unlink this WhatsApp account from NotchFlow?",
                                isPresented: Binding(get: { unlinkSlot != nil }, set: { if !$0 { unlinkSlot = nil } })) {
                Button("Unlink", role: .destructive) {
                    if let slot = unlinkSlot {
                        Task { await manager.unlink(slot) }
                    }
                    unlinkSlot = nil
                }
            } message: {
                Text("NotchFlow is removed from that phone's linked devices. You can link it again by scanning a new QR code.")
            }
        } else if manager.state != .disabled {
            // The accounts (and Add Account) need the connection running;
            // say why they're not here instead of hiding the section.
            Section {
                HStack(alignment: .top) {
                    SettingsRowLabel(title: accountsUnavailableTitle,
                                     detail: "Your accounts show here once the connection runs. Your links are kept.")
                    Spacer()
                    if case .starting = manager.state {
                        ProgressView().controlSize(.small)
                    } else if case .failed = manager.state {
                        Button("Restart") { manager.restartGateway() }
                    }
                }
            } header: {
                Text("Accounts")
            }
        }
    }

    private var accountsUnavailableTitle: String {
        switch manager.state {
        case .notInstalled: return String(localized: "Set up the connection above first.")
        case .installing: return String(localized: "Setting up the connection…")
        case .starting: return String(localized: "Starting the connection…")
        case .failed(let message): return String(localized: "The connection stopped: \(message)")
        default: return String(localized: "The connection isn't running.")
        }
    }

    @ViewBuilder
    private func accountRow(_ slot: WhatsAppAccountSlot) -> some View {
        let state = manager.linkState(for: slot)
        switch state {
        case .connected, .reconnecting:
            HStack(spacing: 8) {
                Circle()
                    .fill(state.isConnected ? SettingsPalette.ok : SettingsPalette.warn)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.isConnected
                         ? String(localized: "Connected as \(manager.phone(for: slot))")
                         : String(localized: "Reconnecting as \(manager.phone(for: slot))…"))
                    if manager.activeSlots.count > 1 {
                        TextField("Name", text: nameBinding(slot), prompt: Text(slot == .primary ? "Business" : "Personal"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                    }
                }
                Spacer()
                Button("Unlink…") {
                    unlinkSlot = slot
                }
                .settingsDestructiveButton()
            }
        case .waitingForLink:
            if slot == .second {
                HStack {
                    Text("Second account")
                        .font(.headline)
                    Spacer()
                    Button("Remove") {
                        Task { await manager.unlink(.second) }
                    }
                    .settingsDestructiveButton()
                }
            }
            linkingView(slot)
        default:
            EmptyView()
        }
    }

    private func nameBinding(_ slot: WhatsAppAccountSlot) -> Binding<String> {
        Binding(get: { accountNames[slot.rawValue] ?? "" },
                set: { manager.setAccountName($0, for: slot) })
    }

    @ViewBuilder
    private func linkingView(_ slot: WhatsAppAccountSlot) -> some View {
        let isMine = manager.isLinking && manager.linkingSlot == slot
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                if isMine, let image = manager.qrImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(8)
                } else if isMine {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 48))
                        .foregroundStyle(.black.opacity(0.25))
                }
            }
            .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 8) {
                Text(slot == .primary ? "Scan with your phone" : "Scan with the other account's phone")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot == .primary ? "1. Open WhatsApp on your phone." : "1. Open WhatsApp of the account to add (on a phone with two WhatsApps, the other app).")
                    Text("2. Go to Settings › Linked devices.")
                    Text("3. Tap Link a device and point the camera at this code.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if isMine {
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
                    Button("Show QR Code") { manager.beginLinking(slot) }
                        .settingsPrimaryButton()
                        .disabled(manager.isLinking)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: Options

    private var notificationSection: some View {
        Section {
            SettingsToggle(key: .whatsAppShowIncomingMessages, title: "Show new messages in the notch",
                           detail: "The notch opens for a moment with who wrote.")
            if showIncomingMessages {
                Group {
                    SettingsToggle(key: .whatsAppShowMessagePreviews, title: "Show the message text")
                    SettingsToggle(key: .whatsAppMuteGroups, title: "Mute groups",
                                   detail: "Unless someone mentions you.",
                                   highlightID: highlightID("Mute groups"))
                    SettingsToggle(key: .whatsAppQuietDuringFocus, title: "Stay quiet during a Focus")
                }
                .padding(.leading, 16)
            }
        } header: {
            Text("New messages")
        }
    }

    private var readingSection: some View {
        Section {
            SettingsToggle(key: .whatsAppMarkReadOnOpen, title: "Mark as read when I open a chat",
                           detail: "Off: only when you reply. Never just because a message arrived.",
                           highlightID: highlightID("Mark as read when I open a conversation"))
        } header: {
            Text("Read receipts")
        }
    }

    private var ignoredSection: some View {
        Section {
            if ignoredChats.isEmpty {
                Text("None. Right-click a chat in the notch and choose Ignore This Chat.")
                    .font(.callout)
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
        }
    }

    private var advancedSection: some View {
        Section {
            HStack {
                SettingsRowLabel(title: "Remove the connection",
                                 detail: "Unlinks your accounts and deletes the local copy of your chats.")
                Spacer()
                Button("Show in Finder") {
                    let url = WhatsAppGatewayInstaller.rootDirectory
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Remove…") {
                    confirmRemove = true
                }
                .settingsDestructiveButton()
                .disabled(!WhatsAppGatewayInstaller.isInstalled)
            }
        } header: {
            Text("Data")
        }
        .confirmationDialog("Remove the WhatsApp connection?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                Task { await manager.removeGateway() }
            }
        } message: {
            Text("Your accounts are unlinked and the local copy of your chats is deleted. Your chats on your phone stay.")
        }
    }
}
