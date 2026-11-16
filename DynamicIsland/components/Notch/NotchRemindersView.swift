// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import EventKit
import SwiftUI

/// Compact Open/Done todos inside the same bounds as the music tab.
struct NotchRemindersView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = RemindersManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var showingDone = false
    @State private var page = 0
    @State private var isComposing = false
    @State private var title = ""
    @State private var creationListID = ""
    @State private var hasDueDate = false
    @State private var includesTime = false
    @State private var dueDate = Date()
    @State private var parsingReferenceDate = Date()
    @State private var manuallySetDate = false
    @State private var keepDateAsText = false
    @State private var interactionToken = UUID()
    @FocusState private var titleFocused: Bool

    private var scopedReminders: [ReminderItem] {
        manager.reminders.filter { manager.selectedListID == nil || $0.listID == manager.selectedListID }
    }
    private var filteredReminders: [ReminderItem] {
        scopedReminders.filter { $0.isCompleted == showingDone }
    }
    private var parsedInput: ParsedReminderInput? {
        guard !keepDateAsText else { return nil }
        return ReminderDateParser.parse(title, referenceDate: parsingReferenceDate)
    }

    var body: some View {
        VStack(spacing: 6) {
            if manager.access == .authorized {
                if isComposing { composer } else {
                    GeometryReader { geometry in
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            todoList(now: context.date, availableHeight: geometry.size.height)
                        }
                    }
                }
            } else { accessState }
            if let error = manager.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2).textSelection(.enabled).help(error)
                    Spacer(minLength: 0)
                    Button { manager.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Dismiss error")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .task {
            manager.showCompleted = showingDone
            await manager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task { await manager.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await manager.refresh() }
        }
        .onChange(of: showingDone) { _, done in manager.showCompleted = done; page = 0 }
        .onChange(of: manager.showCompleted) { _, _ in Task { await manager.refresh() } }
        .onChange(of: manager.selectedListID) { _, _ in page = 0 }
        .onChange(of: manager.isRequestingAccess) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: isComposing) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: title) { _, _ in updateDetectedDate() }
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: interactionToken)
            vm.setAutoCloseSuppression(false, token: interactionToken)
        }
    }

    private func todoList(now: Date, availableHeight: CGFloat) -> some View {
        let rowsPerPage = max(1, min(5, Int(max(0, availableHeight - 50) / 34)))
        let items = filteredReminders
        let pageCount = max(1, (items.count + rowsPerPage - 1) / rowsPerPage)
        let currentPage = min(max(0, page), pageCount - 1)
        let lower = min(items.count, currentPage * rowsPerPage)
        let upper = min(items.count, lower + rowsPerPage)
        return VStack(spacing: 6) {
            todoHeader(now: now)
            HStack(spacing: 6) {
                statusPill("Open", count: scopedReminders.filter { !$0.isCompleted }.count, done: false)
                statusPill("Done", count: showingDone ? items.count : nil, done: true)
                Spacer(minLength: 0)
                if !showingDone {
                    HStack(spacing: 5) {
                        Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(currentPage == 0).help("Previous todos page")
                        Text("\(currentPage + 1)/\(pageCount)").monospacedDigit().frame(minWidth: 25)
                        Button { page = min(pageCount - 1, currentPage + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(currentPage + 1 >= pageCount).help("Next todos page")
                    }
                    .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05), in: Capsule())
                }
                Button(action: beginComposing) {
                    Label("Add", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(manager.writableLists.isEmpty || manager.isLoading)
                .help("Add a todo")
            }
            if manager.isLoading && items.isEmpty {
                ProgressView("Loading todos…").controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else if showingDone {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in reminderRow(item, now: now) }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.visible)
                .onHover { hovering in
                    vm.setScrollGestureSuppression(hovering, token: interactionToken)
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(items[lower..<upper])) { item in reminderRow(item, now: now) }
                    Spacer(minLength: 0)
                }
                .onChange(of: items.map(\.id)) { _, _ in page = min(page, pageCount - 1) }
            }
        }
    }

    private func todoHeader(now: Date) -> some View {
        let open = scopedReminders.filter { !$0.isCompleted }
        let overdue = open.filter { $0.isOverdue(at: now) }.count
        let today = open.filter { $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false }.count
        return HStack {
            Menu {
                Button("All Lists") { manager.selectedListID = nil }
                Divider()
                ForEach(manager.lists) { list in
                    Button("\(list.title) — \(list.account)") { manager.selectedListID = list.id }
                }
                Divider()
                Button("Refresh") { Task { await manager.refresh() } }
                Button("Open Apple Reminders", action: openReminders)
            } label: {
                HStack(spacing: 4) {
                    Text("Todos").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(manager.lists.first(where: { $0.id == manager.selectedListID })?.title ?? "All reminder lists")
            Spacer()
            Text("\(overdue) overdue · \(today) today")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func statusPill(_ title: String, count: Int?, done: Bool) -> some View {
        let selected = showingDone == done
        return Button { showingDone = done } label: {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").opacity(0.65) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(selected ? appearance.accentForegroundColor : Color.white.opacity(0.65))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(selected ? appearance.accentColor : Color.white.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func reminderRow(_ item: ReminderItem, now: Date) -> some View {
        let list = manager.lists.first { $0.id == item.listID }
        let listColor = list.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .accentColor
        let overdue = item.isOverdue(at: now)
        return HStack(spacing: 9) {
            Button {
                Task { await manager.setCompleted(item, completed: !item.isCompleted) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(item.isCompleted ? Color.accentColor : Color.gray)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!item.allowsChanges || manager.pendingIDs.contains(item.id))
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete todo")
            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading).help(item.title)
            if manager.pendingIDs.contains(item.id) { ProgressView().controlSize(.mini) }
            if let label = dueLabel(item, now: now) {
                Text(label).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.secondary : (overdue ? Color.red : Color.accentColor))
                    .lineLimit(1)
            }
            if !item.allowsChanges { Image(systemName: "lock").font(.system(size: 8)).foregroundStyle(.secondary) }
            Circle().fill(listColor).frame(width: 5, height: 5).help(list?.title ?? "Reminder list")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background { NotchElementSurface(cornerRadius: 12) }
    }

    private func dueLabel(_ item: ReminderItem, now: Date) -> String? {
        if item.isCompleted, let completed = item.completionDate {
            if Calendar.current.isDate(completed, inSameDayAs: now) {
                return "Done " + completed.formatted(date: .omitted, time: .shortened)
            }
            return "Done " + completed.formatted(date: .abbreviated, time: .omitted)
        }
        guard let date = item.dueDate else { return nil }
        let calendar = Calendar.current
        let time = item.hasDueTime ? " " + date.formatted(date: .omitted, time: .shortened) : ""
        if item.isOverdue(at: now) {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
            return days > 0 ? "\(days)d overdue" : "Overdue" + time
        }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" + time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow" + time
        }
        return date.formatted(date: .abbreviated, time: item.hasDueTime ? .shortened : .omitted)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(manager.lists.isEmpty ? "No reminder lists" : (showingDone ? "No completed todos" : "All caught up"))
                .font(.system(size: 12, weight: .medium))
            Text(manager.lists.isEmpty ? "Create a list in Apple Reminders, then refresh." : "Choose Add or another list from the Todos menu.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if manager.writableLists.isEmpty { Button("Open Apple Reminders", action: openReminders).controlSize(.small) }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Add todo").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel") { isComposing = false }.controlSize(.small).disabled(manager.isSaving)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    TextField("e.g. Send invoice tomorrow 7 pm", text: $title)
                        .textFieldStyle(.roundedBorder).focused($titleFocused).onSubmit(saveReminder)
                    if let parsed = parsedInput, hasDueDate {
                        HStack(spacing: 6) {
                            Label("Detected: \(parsed.matchedText)", systemImage: "calendar")
                                .font(.caption2).foregroundStyle(Color.accentColor).lineLimit(1)
                            Spacer(minLength: 0)
                            Button("Keep as text") {
                                keepDateAsText = true
                                manuallySetDate = false
                                hasDueDate = false
                            }.font(.caption2).buttonStyle(.plain)
                        }
                        Text("Title: \(parsed.title)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    } else if keepDateAsText {
                        HStack {
                            Text("Date phrase kept in title").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("Detect dates") { keepDateAsText = false; manuallySetDate = false; updateDetectedDate() }
                                .font(.caption2).buttonStyle(.plain)
                        }
                    }
                    Picker("List", selection: $creationListID) {
                        ForEach(manager.writableLists) { list in Text("\(list.title) — \(list.account)").tag(list.id) }
                    }.controlSize(.small)
                    HStack {
                        Toggle("Due date", isOn: Binding(get: { hasDueDate }, set: { hasDueDate = $0; manuallySetDate = true }))
                        if hasDueDate {
                            Toggle("Include time", isOn: Binding(get: { includesTime }, set: { includesTime = $0; manuallySetDate = true }))
                        }
                        Spacer()
                    }.toggleStyle(.checkbox).font(.caption)
                    if hasDueDate {
                        DatePicker("Due", selection: Binding(get: { dueDate }, set: { dueDate = $0; manuallySetDate = true }),
                                   displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                            .controlSize(.small)
                    }
                }.padding(.vertical, 2)
            }
            .onHover { hovering in vm.setScrollGestureSuppression(hovering, token: interactionToken) }
            HStack {
                if hasDueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: includesTime ? .shortened : .omitted))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("No due date").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if manager.isSaving { ProgressView().controlSize(.small) }
                Button("Add Todo", action: saveReminder)
                    .controlSize(.small)
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
        parsingReferenceDate = Date()
        manuallySetDate = false
        keepDateAsText = false
        isComposing = true
        titleFocused = true
    }

    private func updateDetectedDate() {
        guard !manuallySetDate, !keepDateAsText else { return }
        parsingReferenceDate = Date()
        if let parsed = parsedInput {
            hasDueDate = true
            includesTime = parsed.includesTime
            dueDate = parsed.dueDate
        } else {
            hasDueDate = false
            includesTime = false
        }
    }

    private func saveReminder() {
        let input = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let parsed = parsedInput
        let savingDate = manuallySetDate ? (hasDueDate ? dueDate : nil) : (parsed?.dueDate ?? (hasDueDate ? dueDate : nil))
        let savingTime = manuallySetDate ? includesTime : (parsed?.includesTime ?? includesTime)
        let savingTitle = savingDate != nil ? (parsed?.title ?? input) : input
        Task {
            if await manager.create(title: savingTitle, listID: creationListID,
                                    dueDate: savingDate, includesTime: savingTime) {
                if manager.selectedListID != nil { manager.selectedListID = creationListID }
                isComposing = false
                showingDone = false
                page = 0
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
