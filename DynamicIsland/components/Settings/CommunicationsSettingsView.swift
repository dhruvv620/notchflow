// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import AppKit
import Defaults
import SwiftUI

struct CommunicationsSettingsView: View {
    @ObservedObject private var manager = CommunicationsManager.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared
    @Default(.communicationsEnabled) private var enabled
    @Default(.communicationNotificationApps) private var notificationApps
    @Default(.communicationCallApps) private var callApps
    @Default(.communicationShowPreviews) private var showPreviews
    @Default(.communicationRespectFocus) private var respectFocus
    @Default(.notificationReadCenterHistory) private var readCenterHistory
    @Default(.notificationMutedApps) private var mutedApps
    @ObservedObject private var hub = NotificationHub.shared
    @ObservedObject private var fullDiskAccess = FullDiskAccessPermissionStore.shared
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @State private var confirmErase = false

    var body: some View {
        Form {
            if !enabled {
                Section {
                    Text("Off: notifications and calls aren't collected or shown in the notch.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                accessSection
                sourcesSection
                alertsSection
                Section {
                    ForEach(CommunicationApp.allCases) { app in
                        appToggle(app, selection: $notificationApps)
                    }
                } header: {
                    Text("Banner actions for")
                } footer: {
                    Text("Reply, Open and Close from the real banner while it's on screen.")
                }
                .settingsHighlight(id: "communications-Notification apps")
                mutedSection
                callsSection
                dataSection
            }
        }
        .onAppear { manager.refreshAccess() }
        .onChange(of: enabled) { _, _ in manager.refreshAccess() }
    }

    // MARK: Sections

    @ViewBuilder private var accessSection: some View {
        Section {
            HStack {
                SettingsRowLabel(title: "Accessibility", detail: "Reads banners and call buttons on screen.")
                Spacer()
                if manager.accessGranted {
                    SettingsStatus(text: "Allowed", kind: .ok)
                } else {
                    Button("Open Settings", action: accessibilityPermission.openSystemSettings)
                    Button("Allow", action: manager.requestAccess)
                        .settingsPrimaryButton()
                }
            }
            if !manager.accessGranted {
                SettingsStatus(text: accessibilityPermission.recoveryMessage ?? "Already allowed but not working? An older copy of NotchFlow may hold the permission.", kind: .warn)
                HStack {
                    Spacer()
                    Button("Show This Copy", action: accessibilityPermission.revealRunningApplication)
                    Button(accessibilityPermission.isRepairing ? "Fixing…" : "Fix Old Entries") {
                        Task { await accessibilityPermission.repairAuthorization() }
                    }
                    .disabled(accessibilityPermission.isRepairing)
                    Button("Check Again", action: manager.refreshAccess)
                }
            }
            if let error = manager.lastError {
                SettingsStatus(text: error, kind: .error)
            }
        } header: {
            Text("Access")
        } footer: {
            Text("NotchFlow never reads your apps' message databases.")
        }
    }

    private var sourcesSection: some View {
        Section {
            Toggle(isOn: $readCenterHistory) {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsRowLabel(title: "Notification Center",
                                     detail: "Every app's notifications, even ones you missed. Only read, never changed.")
                    if readCenterHistory {
                        SettingsStatus(text: hub.centerState.message,
                                       kind: hub.centerState == .reading ? .ok : .warn)
                    }
                }
            }
            if readCenterHistory && hub.centerState == .needsFullDiskAccess {
                HStack {
                    SettingsRowLabel(title: "Needs Full Disk Access")
                    Spacer()
                    Button("Allow") { fullDiskAccess.requestAccessPrompt() }
                        .settingsPrimaryButton()
                }
                .padding(.leading, 16)
            }
            LabeledContent {
                SettingsStatus(text: manager.accessGranted ? "On" : "Needs Accessibility",
                               kind: manager.accessGranted ? .ok : .warn)
            } label: {
                SettingsRowLabel(title: "Banners on screen", detail: "Adds Reply and Open from the banner itself.")
            }
            LabeledContent {
                SettingsStatus(text: whatsApp.state.isLinked ? "Linked" : "Not linked",
                               kind: whatsApp.state.isLinked ? .ok : .neutral)
            } label: {
                SettingsRowLabel(title: "WhatsApp", detail: "Messages from your linked account. Set it up on the WhatsApp page.")
            }
        } header: {
            Text("Where notifications come from")
        }
    }

    private var alertsSection: some View {
        Section {
            SettingsToggle(key: .notificationAlertInNotch, title: "Show new ones in the closed notch")
            Toggle(isOn: $showPreviews) {
                SettingsRowLabel(title: "Show previews", detail: "The message text and who's calling.")
            }
            SettingsToggle(key: .notificationClearOnReply, title: "Clear a chat when I reply",
                           detail: "Reply once, from anywhere, and that person's messages leave the inbox.")
            Toggle("Stay quiet during a Focus", isOn: $respectFocus)
        } header: {
            Text("Alerts and replies")
        } footer: {
            Text("Messages replies go through the Messages app. Other apps take replies only while their banner is on screen; otherwise use Open.")
        }
    }

    private var mutedSection: some View {
        Section {
            if mutedApps.isEmpty {
                Text("None. Right-click a notification in the notch and choose Mute.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(mutedApps, id: \.self) { bundle in
                    HStack(spacing: 8) {
                        NotificationAppIcon(bundleIdentifier: bundle, appName: hub.appName(for: bundle), size: 18)
                        Text(hub.appName(for: bundle))
                        Spacer()
                        Button("Unmute") { hub.unmute(bundle) }
                    }
                }
            }
        } header: {
            Text("Muted apps")
        }
    }

    private var callsSection: some View {
        Section {
            ForEach([CommunicationApp.faceTime, .phone, .whatsapp, .teams, .zoom]) { app in
                appToggle(app, selection: $callApps)
            }
        } header: {
            Text("Calls")
        } footer: {
            Text("Incoming calls come first in the notch, with answer, mute and end when the app offers them. iPhone calls need to be set up to ring on this Mac.")
        }
        .settingsHighlight(id: "communications-Call Island")
    }

    private var dataSection: some View {
        Section {
            HStack {
                SettingsRowLabel(title: "Erase stored notifications",
                                 detail: "\(hub.items.count) kept, up to 200. Notification Center keeps its own copy.")
                Spacer()
                Button("Erase…") { confirmErase = true }
                    .settingsDestructiveButton()
                    .disabled(hub.items.isEmpty)
            }
        } header: {
            Text("Data")
        }
        .confirmationDialog("Erase every notification stored by NotchFlow?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) {
                hub.eraseHistory()
                manager.clearHistory()
            }
        } message: {
            Text("This only affects NotchFlow's inbox.")
        }
    }

    private func appToggle(_ app: CommunicationApp, selection: Binding<[String]>) -> some View {
        Toggle(isOn: Binding(get: { selection.wrappedValue.contains(app.rawValue) }, set: { shown in
            var values = Set(selection.wrappedValue)
            if shown { values.insert(app.rawValue) } else { values.remove(app.rawValue) }
            selection.wrappedValue = values.sorted()
        })) {
            Label(app.title, systemImage: app.symbol)
        }
    }
}
