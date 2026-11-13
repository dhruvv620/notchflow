// SPDX-License-Identifier: GPL-3.0-or-later
import Defaults
import SwiftUI

struct CommunicationsInboxView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = CommunicationsManager.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared
    @Default(.communicationsEnabled) private var enabled
    @Default(.communicationShowPreviews) private var showPreviews
    @State private var replyTarget: CommunicationNotification?
    @State private var draft = ""
    @State private var busyID: String?
    @State private var token = UUID()
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if !enabled {
                state("Notifications are off", detail: "Enable Communications to collect visible notifications from selected apps.") {
                    Button("Enable Communications") { enabled = true; manager.refreshAccess() }
                }
            } else if !manager.accessGranted {
                state("Accessibility access is needed", detail: permissionDetail) {
                    Button("Allow Access", action: manager.requestAccess)
                    Button("Check Access", action: manager.refreshAccess)
                    Button("Repair") { Task { await accessibilityPermission.repairAuthorization() } }
                        .disabled(accessibilityPermission.isRepairing)
                }
            } else {
                ScrollView {
                    if let target = replyTarget { composer(target) }
                    else if manager.notifications.isEmpty {
                        state("Your recent notifications appear here", detail: "Only notifications exposed by selected apps can be collected. Recent items stay on this Mac until cleared or the app quits.") { EmptyView() }
                    } else {
                        LazyVStack(spacing: 5) {
                            ForEach(manager.notifications) { item in row(item) }
                        }
                    }
                }
                .onHover { vm.setScrollGestureSuppression($0, token: token) }
            }
            if let error = manager.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2).help(error)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .task { manager.refreshAccess(); await manager.refresh() }
        .onChange(of: replyTarget?.id) { _, _ in updateSuppression() }
        .onChange(of: busyID) { _, _ in updateSuppression() }
        .onChange(of: enabled) { _, value in if !value { cancelReply() } }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: token)
            vm.setScrollGestureSuppression(false, token: token)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Notifications").font(.system(size: 13, weight: .semibold))
            Text("\(manager.notifications.count) / 20").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await manager.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(manager.isRefreshing || busyID != nil).help("Refresh notifications")
            Button { manager.clearHistory(); cancelReply() } label: { Image(systemName: "trash") }
                .disabled(manager.notifications.isEmpty || busyID != nil).help("Clear this notch's recent notifications")
        }.font(.system(size: 11)).buttonStyle(.plain)
    }

    private func row(_ item: CommunicationNotification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.app.symbol).foregroundStyle(Color.accentColor)
                Text(showPreviews ? item.sender : item.app.title).fontWeight(.semibold).lineLimit(1)
                Text(item.app.title).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.receivedAt, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
            }.font(.system(size: 11))
            Text(showPreviews ? item.body : "Message preview hidden")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                if item.canReply {
                    Button("Reply", systemImage: "arrowshape.turn.up.left") {
                        busyID = item.id
                        Task {
                            if await manager.beginReply(id: item.id) {
                                replyTarget = item; draft = ""; replyFocused = true
                            }
                            busyID = nil
                        }
                    }
                }
                Button(item.canOpen ? "Open" : "Open app", systemImage: "arrow.up.right") {
                    busyID = item.id
                    Task {
                        if item.canOpen { await manager.openNotification(id: item.id) }
                        else { manager.openSource(item.app) }
                        busyID = nil
                    }
                }
                Spacer(minLength: 0)
                if busyID == item.id { ProgressView().controlSize(.mini) }
                Button {
                    busyID = item.id
                    Task { await manager.dismissNotification(id: item.id); busyID = nil }
                } label: { Image(systemName: "xmark") }
                .help(item.canDismiss ? "Dismiss notification" : "Remove from this notch")
                .accessibilityLabel("Dismiss notification from \(item.app.title)")
            }
            .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
            .foregroundStyle(Color.accentColor).disabled(busyID != nil)
        }
        .padding(8)
        .background { NotchElementSurface(cornerRadius: 10) }
    }

    private func composer(_ target: CommunicationNotification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Reply to \(target.sender)", systemImage: target.app.symbol)
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(target.app.title).font(.caption2).foregroundStyle(.secondary)
            }
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...3).font(.system(size: 12)).textFieldStyle(.roundedBorder)
                .focused($replyFocused).disabled(busyID != nil)
                .accessibilityLabel("Message to \(target.sender)")
            HStack {
                Button("Cancel", action: cancelReply).disabled(busyID != nil)
                Spacer()
                if busyID != nil { ProgressView().controlSize(.mini) }
                Button("Send", systemImage: "paperplane.fill") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, busyID == nil else { return }
                    busyID = target.id
                    Task {
                        if await manager.sendReply(text, id: target.id) { cancelReply() }
                        busyID = nil
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busyID != nil)
            }.font(.system(size: 11)).controlSize(.small)
        }.padding(8).background { NotchElementSurface(cornerRadius: 10) }
    }

    private func state<Actions: View>(_ title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 8, content: actions).controlSize(.small)
        }.padding(.vertical, 6).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var permissionDetail: String {
        accessibilityPermission.recoveryMessage
            ?? "Grant access to this exact NotchFlow copy. If macOS shows duplicate NotchFlow rows, choose Repair and approve the new prompt."
    }
    private func cancelReply() { replyTarget = nil; draft = ""; replyFocused = false }
    private func updateSuppression() {
        let active = replyTarget != nil || busyID != nil
        vm.setAutoCloseSuppression(active, token: token)
        if !active { vm.shouldRecheckHover.toggle() }
    }
}
