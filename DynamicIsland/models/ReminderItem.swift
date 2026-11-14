// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct ReminderListItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let account: String
    let red: Double
    let green: Double
    let blue: Double
    let allowsChanges: Bool
}

struct ReminderItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let listID: String
    let isCompleted: Bool
    let dueDate: Date?
    let hasDueTime: Bool
    let allowsChanges: Bool
    let completionDate: Date?

    init(
        id: String,
        title: String,
        listID: String,
        isCompleted: Bool,
        dueDate: Date?,
        hasDueTime: Bool,
        allowsChanges: Bool,
        completionDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.listID = listID
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.allowsChanges = allowsChanges
        self.completionDate = completionDate
    }

    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        if hasDueTime { return dueDate < now }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }
}

struct ReminderSnapshot: Sendable {
    let lists: [ReminderListItem]
    let reminders: [ReminderItem]
    let defaultListID: String?
}

enum ReminderAccess: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted
}

enum ReminderPolicy {
    /// Open reminders use earliest due date. Completed reminders use newest
    /// completion date so the Done section reads as a useful activity history.
    static func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }

            if lhs.isCompleted {
                let lhsDate = lhs.completionDate ?? lhs.dueDate ?? .distantPast
                let rhsDate = rhs.completionDate ?? rhs.dueDate ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
            } else if lhs.dueDate != rhs.dueDate {
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }

            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    /// A date-only reminder must not acquire a time or UTC offset when saved to EventKit.
    static func dueComponents(for date: Date, includesTime: Bool, calendar: Calendar = .current) -> DateComponents {
        let fields: Set<Calendar.Component> = includesTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        var components = calendar.dateComponents(fields, from: date)
        components.calendar = calendar
        if includesTime { components.timeZone = calendar.timeZone }
        return components
    }
}
