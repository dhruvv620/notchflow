// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit
import Foundation

@MainActor
protocol RemindersServiceProviding {
    var access: ReminderAccess { get }
    func requestAccess() async throws -> Bool
    func snapshot(includeCompleted: Bool) async throws -> ReminderSnapshot
    func create(title: String, listID: String, dueDate: Date?, includesTime: Bool) throws
    func setCompleted(id: String, completed: Bool) throws
}

enum ReminderServiceError: LocalizedError {
    case accessRequired, fetchFailed, listUnavailable, readOnly, reminderUnavailable, emptyTitle

    var errorDescription: String? {
        switch self {
        case .accessRequired: return String(localized: "Allow Reminders access in System Settings → Privacy & Security → Reminders.")
        case .fetchFailed: return String(localized: "Reminders could not be loaded. Try refreshing.")
        case .listUnavailable: return String(localized: "This reminder list is no longer available. Choose another list.")
        case .readOnly: return String(localized: "This list is read-only. Choose a list you can edit.")
        case .reminderUnavailable: return String(localized: "This reminder is no longer available. Refresh the list.")
        case .emptyTitle: return String(localized: "Enter a title for the reminder.")
        }
    }
}

/// Shares Apple's Reminders data through EventKit; does not maintain a second reminder database.
@MainActor
final class EventKitRemindersService: RemindersServiceProviding {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) { self.store = store }

    var access: ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied
        }
    }

    func requestAccess() async throws -> Bool {
        switch access {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined: break
        }
        // The notch is a nonactivating panel. Bring this explicit user request
        // to the foreground before macOS presents its privacy dialog.
        NSApplication.shared.activate()
        await Task.yield()
        return try await store.requestFullAccessToReminders()
    }

    func snapshot(includeCompleted: Bool) async throws -> ReminderSnapshot {
        guard access == .authorized else { throw ReminderServiceError.accessRequired }
        let calendars = store.calendars(for: .reminder)
        let lists = calendars.map { calendar -> ReminderListItem in
            let color = calendar.color.usingColorSpace(.deviceRGB) ?? NSColor(deviceRed: 0.2, green: 0.45, blue: 0.95, alpha: 1)
            return ReminderListItem(
                id: calendar.calendarIdentifier, title: calendar.title,
                account: calendar.source.title,
                red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent),
                allowsChanges: calendar.allowsContentModifications
            )
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard !calendars.isEmpty else {
            return ReminderSnapshot(lists: [], reminders: [], defaultListID: nil)
        }
        let predicate = includeCompleted
            ? store.predicateForReminders(in: calendars)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: ReminderServiceError.fetchFailed)
                    return
                }
                continuation.resume(returning: reminders)
            }
        }
        // Permission may have changed while EventKit was fetching.
        guard access == .authorized else { throw ReminderServiceError.accessRequired }
        let items = reminders.compactMap { reminder -> ReminderItem? in
            guard let calendar = reminder.calendar else { return nil }
            let due = reminder.dueDateComponents
            return ReminderItem(
                id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                listID: calendar.calendarIdentifier, isCompleted: reminder.isCompleted,
                dueDate: due.flatMap { ($0.calendar ?? Calendar.current).date(from: $0) },
                hasDueTime: due?.hour != nil,
                allowsChanges: calendar.allowsContentModifications,
                completionDate: reminder.completionDate
            )
        }
        return ReminderSnapshot(
            lists: lists, reminders: ReminderPolicy.sorted(items),
            defaultListID: store.defaultCalendarForNewReminders()?.calendarIdentifier
        )
    }

    func create(title: String, listID: String, dueDate: Date?, includesTime: Bool) throws {
        guard access == .authorized else { throw ReminderServiceError.accessRequired }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ReminderServiceError.emptyTitle }
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == listID }) else {
            throw ReminderServiceError.listUnavailable
        }
        guard calendar.allowsContentModifications else { throw ReminderServiceError.readOnly }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        if let dueDate {
            reminder.dueDateComponents = ReminderPolicy.dueComponents(for: dueDate, includesTime: includesTime)
        }
        try store.save(reminder, commit: true)
    }

    func setCompleted(id: String, completed: Bool) throws {
        guard access == .authorized else { throw ReminderServiceError.accessRequired }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ReminderServiceError.reminderUnavailable
        }
        guard reminder.calendar?.allowsContentModifications == true else { throw ReminderServiceError.readOnly }
        reminder.isCompleted = completed
        // EventKit owns `completionDate` and updates it when `isCompleted` is
        // saved; the property is read-only to clients.
        try store.save(reminder, commit: true)
    }
}
