// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import AppKit
import Defaults
import SwiftUI

struct CommunicationsSettingsView: View {
    @ObservedObject private var manager = CommunicationsManager.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
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
    @State private var section = SectionChoice.notifications
    private enum SectionChoice: String, CaseIterable, Identifiable {
        case notifications = "Notifications", calls = "Calls"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Communications section", selection: $section) {
                ForEach(SectionChoice.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable Communications", isOn: $enabled)
                                .settingsHighlight(id: "communications-Enable Communications")
                            Text("Collect your notifications in the notch, reply without switching apps, and detect call controls. The inbox is kept on this Mac until you clear it.")
                                .font(.caption).foregroundStyle(.secondary)
                            Divider()
                            HStack {
                                Label(manager.accessGranted ? "Accessibility access granted" : "Accessibility access needed", systemImage: manager.accessGranted ? "checkmark.shield" : "hand.raised")
                                    .font(.system(size: 12))
                                Spacer()
                                if !manager.accessGranted { Button("Allow Access", action: manager.requestAccess) }
                                Button("Check Access", action: manager.refreshAccess)
                            }
                            HStack {
                                Button("Open Accessibility Settings", action: accessibilityPermission.openSystemSettings)
                                Button("Reveal This NotchFlow", action: accessibilityPermission.revealRunningApplication)
                                if !manager.accessGranted {
                                    Button(accessibilityPermission.isRepairing ? "Repairing…" : "Repair Stale Entries") {
                                        Task { await accessibilityPermission.repairAuthorization() }
                                    }
                                    .disabled(accessibilityPermission.isRepairing)
                                }
                            }.font(.caption)
                            Text(manager.statusText).font(.caption).foregroundStyle(.secondary)
                            if !manager.accessGranted {
                                Text(accessibilityPermission.recoveryMessage ?? "Accessibility is tied to the exact signed app copy. Duplicate NotchFlow rows usually belong to older local builds; reveal this copy or reset the stale entries before approving it again.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = manager.lastError { Text(error).font(.caption).foregroundStyle(SettingsPalette.warn) }
                        }.padding(6)
                    }
                    if section == .notifications { notificationSettings } else { callSettings }
                    Text("Reading Notification Center needs Full Disk Access; reading on-screen banners and call controls needs Accessibility. NotchFlow never reads your apps' message databases.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { manager.refreshAccess(); selectHighlightedSection(highlightCoordinator.activeHighlightID) }
        .onReceive(highlightCoordinator.$activeHighlightID) { selectHighlightedSection($0) }
        .onChange(of: enabled) { _, _ in manager.refreshAccess() }
    }

    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Where notifications come from") {
                VStack(alignment: .leading, spacing: 12) {
                    sourceRow(
                        title: "Notification Center history",
                        detail: "Every app's notifications, including ones whose banner you missed. Needs Full Disk Access; Notification Center itself is only read, never changed.",
                        ready: readCenterHistory && hub.centerState == .reading,
                        status: readCenterHistory ? hub.centerState.message : "Off"
                    ) {
                        Toggle("Notification Center history", isOn: $readCenterHistory)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        if readCenterHistory && hub.centerState == .needsFullDiskAccess {
                            Button("Allow Full Disk Access") { fullDiskAccess.requestAccessPrompt() }
                        }
                    }
                    Divider()
                    sourceRow(
                        title: "Live banners",
                        detail: "Adds Reply, Open and Close from the real banner while it is on screen, for the apps selected below. Needs Accessibility.",
                        ready: manager.accessGranted,
                        status: manager.accessGranted ? manager.notificationDiagnostics.message : "Accessibility access needed"
                    ) {
                        if !manager.accessGranted { Button("Allow", action: manager.requestAccess) }
                    }
                    Divider()
                    sourceRow(
                        title: "WhatsApp",
                        detail: "Messages from your linked WhatsApp account, with replies that always go through.",
                        ready: whatsApp.state.isLinked,
                        status: whatsApp.state.isLinked ? "Linked" : "Not linked. Set it up in Settings › WhatsApp."
                    ) { EmptyView() }
                }.padding(6)
            }
            GroupBox("Replies") {
                Text("WhatsApp replies go through your linked account. Messages replies are sent through the Messages app, which asks once to allow NotchFlow to control it. Other apps accept replies only while their own banner is still on screen; otherwise use Open.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            GroupBox("Muted apps") {
                VStack(alignment: .leading, spacing: 8) {
                    if mutedApps.isEmpty {
                        Text("Right-click a notification in the notch and choose Mute to stop collecting that app.")
                            .font(.caption).foregroundStyle(.secondary)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            GroupBox("Live banner apps") {
                VStack(spacing: 10) {
                    ForEach(CommunicationApp.allCases) { app in
                        appToggle(app, selection: $notificationApps)
                    }
                }.padding(6)
            }.settingsHighlight(id: "communications-Notification apps")
            GroupBox("Previews and alerts") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show notification and caller previews", isOn: $showPreviews)
                    Defaults.Toggle(key: .notificationAlertInNotch) { Text("Announce new notifications in the closed notch") }
                    Defaults.Toggle(key: .notificationClearOnReply) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear a conversation when I reply")
                            Text("Answer Rahul once and all his messages leave the inbox, whether you replied from the notch, Messages, your phone or WhatsApp.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Respect Focus for notification alerts", isOn: $respectFocus)
                    Text("Reply appears only when the source exposes a native reply action. Otherwise, use Open app. Visible browser notifications may provide fewer actions than desktop apps.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(manager.notificationDiagnostics.message)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("\(hub.items.count) stored · up to 200 kept").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Erase Stored Notifications…") { confirmErase = true }
                            .disabled(hub.items.isEmpty)
                    }
                    .confirmationDialog("Erase every notification stored by NotchFlow?", isPresented: $confirmErase) {
                        Button("Erase", role: .destructive) {
                            hub.eraseHistory()
                            manager.clearHistory()
                        }
                    } message: {
                        Text("This only affects NotchFlow's inbox. Notification Center keeps its own copy.")
                    }
                }.padding(6)
            }
        }
    }
    private var callSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Call apps") {
                VStack(spacing: 10) {
                    ForEach([CommunicationApp.faceTime, .phone, .whatsapp, .teams, .zoom]) { app in
                        appToggle(app, selection: $callApps)
                    }
                }.padding(6)
            }.settingsHighlight(id: "communications-Call Island")
            GroupBox("Call Island") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Incoming calls take priority in the notch. Ongoing calls keep a compact status and duration; your selected tab returns afterward.")
                    Text("Answer, decline, mute, video and end controls appear only when the app exposes them. Open app remains available. iPhone calls must already be configured to work on this Mac.")
                    Text("This prototype recognizes English native controls. Browser calls and changed app layouts may remain unavailable; use Open app in those cases.")
                    Text("If the app does not provide a connection time, the timer is labeled Detected and counts from first observation.")
                }.font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
    }
    private func sourceRow<Controls: View>(title: String, detail: String, ready: Bool, status: String,
                                           @ViewBuilder controls: () -> Controls) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ready ? SettingsPalette.ok : Color.secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(status).font(.caption2).foregroundStyle(ready ? SettingsPalette.ok : SettingsPalette.warn)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6, content: controls).controlSize(.small)
        }
    }

    private func selectHighlightedSection(_ id: String?) {
        if id == "communications-Call Island" { section = .calls }
        else if id == "communications-Notification apps" { section = .notifications }
    }
    private func appToggle(_ app: CommunicationApp, selection: Binding<[String]>) -> some View {
        Toggle(isOn: Binding(get: { selection.wrappedValue.contains(app.rawValue) }, set: { shown in
            var values = Set(selection.wrappedValue)
            if shown { values.insert(app.rawValue) } else { values.remove(app.rawValue) }
            selection.wrappedValue = values.sorted()
        })) {
            Label(app.title, systemImage: app.symbol)
        }.toggleStyle(.switch).controlSize(.small)
    }
}
