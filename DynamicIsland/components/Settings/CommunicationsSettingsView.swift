// SPDX-License-Identifier: GPL-3.0-or-later
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
                            Text("Collect visible notifications and detect call controls from the apps you select. Recent notifications remain in memory until cleared or NotchFlow quits.")
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
                            if let error = manager.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                        }.padding(6)
                    }
                    if section == .notifications { notificationSettings } else { callSettings }
                    Text("macOS notification permission covers NotchFlow’s own alerts. Reading other apps’ visible controls requires Accessibility access; it does not grant access to private message histories.")
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
            GroupBox("Notification apps") {
                VStack(spacing: 10) {
                    ForEach(CommunicationApp.allCases) { app in
                        appToggle(app, selection: $notificationApps)
                    }
                }.padding(6)
            }.settingsHighlight(id: "communications-Notification apps")
            GroupBox("Previews and alerts") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show notification and caller previews", isOn: $showPreviews)
                    Toggle("Respect Focus for notification alerts", isOn: $respectFocus)
                    Text("Reply appears only when the source exposes a native reply action. Otherwise, use Open app. Visible browser notifications may provide fewer actions than desktop apps.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("\(manager.notifications.count) recent items · maximum 20").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear recent notifications", action: manager.clearHistory).disabled(manager.notifications.isEmpty)
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
