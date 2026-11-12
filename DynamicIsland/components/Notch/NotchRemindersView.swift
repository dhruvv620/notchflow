// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import EventKit
import SwiftUI

/// A compact EventKit list inside Atoll's existing tab shell.
struct NotchRemindersView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = RemindersManager.shared
    @State private var isComposing = false
    @State private var title = ""
    @State private var creationListID = ""
    @State private var hasDueDate = false
    @State private var includesTime = false
    @State private var dueDate = Date()
    @State private var interactionToken = UUID()
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            if manager.access == .authorized {
                if isComposing { composer } else { reminderList }
            } else {
                accessState
            }
            if let error = manager.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { manager.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Dismiss error")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .task { await manager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task { await manager.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await manager.refresh() }
        }
        .onChange(of: manager.showCompleted) { _, _ in Task { await manager.refresh() } }
        .onChange(of: manager.isRequestingAccess) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: isComposing) { _, _ in updateAutoCloseSuppression() }
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: interactionToken)
            vm.setAutoCloseSuppression(false, token: interactionToken)
        }
    }

    private var reminderList: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label("Reminders", systemImage: "checklist").font(.system(size: 16, weight: .semibold))
                Text("\(manager.visibleReminders.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("All Lists") { manager.selectedListID = nil }
                    Divider()
                    ForEach(manager.lists) { list in
                        Button { manager.selectedListID = list.id } label: {
                            Text("\(list.title) — \(list.account)")
                        }
                    }
                } label: {
                    Text(manager.lists.first(where: { $0.id == manager.selectedListID })?.title ?? String(localized: "All Lists"))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 160)
                .layoutPriority(-1)
                .help(manager.lists.first(where: { $0.id == manager.selectedListID })?.title ?? String(localized: "Choose reminder list"))
                Menu {
                    Toggle("Show completed", isOn: $manager.showCompleted)
                    Button("Open Apple Reminders") { openReminders() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("Reminder options")
                Button { Task { await manager.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(manager.isLoading).help("Refresh reminders")
                Button(action: beginComposing) { Image(systemName: "plus") }
                    .buttonStyle(.plain).disabled(manager.writableLists.isEmpty || manager.isLoading)
                    .help("New reminder")
            }
            if manager.isLoading && manager.reminders.isEmpty {
                ProgressView("Loading reminders…").controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.visibleReminders.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.visibleReminders) { item in reminderRow(item) }
                    }
                }
                .onHover { hovering in vm.setScrollGestureSuppression(hovering, token: interactionToken) }
            }
        }
    }

    private func reminderRow(_ item: ReminderItem) -> some View {
        let list = manager.lists.first { $0.id == item.listID }
        let accent = list.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .accentColor
        return HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await manager.setCompleted(item, completed: !item.isCompleted) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(item.isCompleted ? .secondary : accent)
            }
            .buttonStyle(.plain)
            .disabled(!item.allowsChanges || manager.pendingIDs.contains(item.id))
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete reminder")
            .help(item.allowsChanges ? "Toggle completion" : "Read-only reminder")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .medium))
                    .strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if manager.selectedListID == nil, let list {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(list.title).lineLimit(1)
                    }
                    if let dueDate = item.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: item.hasDueTime ? .shortened : .omitted))
                            .foregroundStyle(item.isOverdue(at: Date()) ? .red : .secondary)
                    }
                    if !item.allowsChanges { Image(systemName: "lock").help("Read-only list") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if manager.pendingIDs.contains(item.id) { ProgressView().controlSize(.mini) }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(manager.lists.isEmpty ? "No reminder lists" : "All caught up").font(.headline)
            Text(manager.lists.isEmpty
                 ? "Create a list in Apple Reminders, then refresh here."
                 : "Add a reminder, choose another list, or show completed items.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if manager.writableLists.isEmpty {
                Button("Open Apple Reminders", action: openReminders)
            } else {
                Button("New reminder", action: beginComposing)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessState: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Apple Reminders").font(.headline)
                Text(permissionDescription)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if manager.access == .notDetermined {
                    Button(manager.isRequestingAccess ? "Waiting for macOS…" : "Allow Reminders access") {
                        Task { await manager.requestAccess() }
                    }
                    .disabled(manager.isRequestingAccess)
                    .accessibilityIdentifier("RemindersAllowAccess")
                }
                if manager.isRequestingAccess {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Check for a macOS permission dialog.").font(.caption)
                    }
                }
                HStack(spacing: 12) {
                    Button("Open Privacy Settings", action: openReminderPrivacySettings)
                        .accessibilityIdentifier("RemindersPrivacySettings")
                    Button("Check Access") { Task { await manager.refresh() } }
                        .accessibilityIdentifier("RemindersCheckAccess")
                }
                if manager.permissionNeedsAttention {
                    Text("macOS has not finished the request. You can check the Reminders privacy settings, then choose Check Access. If no permission entry appears, quit and reopen NotchFlow and try again.")
                        .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .onHover { hovering in vm.setScrollGestureSuppression(hovering, token: interactionToken) }
    }

    private var permissionDescription: String {
        switch manager.access {
        case .restricted:
            return String(localized: "Reminders access is restricted on this Mac.")
        case .denied:
            return String(localized: "Enable NotchFlow in System Settings → Privacy & Security → Reminders, then choose Check Access.")
        default:
            return String(localized: "View your lists, add reminders, and mark them complete. Changes sync through Apple Reminders.")
        }
    }

    private func openReminderPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Reminder").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Cancel") { isComposing = false }.disabled(manager.isSaving)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("What do you need to do?", text: $title)
                        .textFieldStyle(.roundedBorder).focused($titleFocused).onSubmit(saveReminder)
                    Picker("List", selection: $creationListID) {
                        ForEach(manager.writableLists) { list in Text("\(list.title) — \(list.account)").tag(list.id) }
                    }
                    HStack {
                        Toggle("Due date", isOn: $hasDueDate)
                        if hasDueDate { Toggle("Include time", isOn: $includesTime) }
                        Spacer()
                    }.toggleStyle(.checkbox)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    }
                }
                .padding(.vertical, 2)
            }
            .onHover { hovering in vm.setScrollGestureSuppression(hovering, token: interactionToken) }
            HStack {
                Text("Saved to Apple Reminders").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if manager.isSaving { ProgressView().controlSize(.small) }
                Button("Add Reminder", action: saveReminder)
                    .disabled(manager.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || !manager.writableLists.contains(where: { $0.id == creationListID }))
            }
        }
        .disabled(manager.isSaving)
    }

    private func beginComposing() {
        guard let id = manager.preferredCreationListID else { return }
        title = ""
        creationListID = id
        hasDueDate = false
        includesTime = false
        dueDate = Date()
        isComposing = true
        titleFocused = true
    }

    private func saveReminder() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            if await manager.create(title: title, listID: creationListID,
                                    dueDate: hasDueDate ? dueDate : nil, includesTime: includesTime) {
                isComposing = false
            }
        }
    }

    private func updateAutoCloseSuppression() {
        vm.setAutoCloseSuppression(isComposing || manager.isRequestingAccess, token: interactionToken)
    }

    private func openReminders() {
        if let url = URL(string: "x-apple-reminderkit://") { NSWorkspace.shared.open(url) }
    }
}
