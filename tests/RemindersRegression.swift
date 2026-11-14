// SPDX-License-Identifier: GPL-3.0-or-later
// Compile on macOS with ReminderItem.swift, RemindersServiceProviding.swift, and RemindersManager.swift.

import Foundation

@MainActor
private final class FakeRemindersService: RemindersServiceProviding {
    var access: ReminderAccess = .authorized
    var fetchCount = 0
    var requestedAccess = false
    var requestCount = 0
    var requestResult = true
    var accessAfterRequest: ReminderAccess = .authorized
    var failRequest = false
    var waitForRequest = false
    var permissionContinuation: CheckedContinuation<Bool, Error>?
    var savedTitles: [String] = []
    var completedIDs: [String] = []
    var failCreate = false
    var failCompletion = false
    var lists: [ReminderListItem] = [
        .init(id: "read-only", title: "Shared", account: "iCloud", red: 0, green: 0, blue: 1, allowsChanges: false),
        .init(id: "writable", title: "Personal", account: "iCloud", red: 0, green: 0, blue: 1, allowsChanges: true)
    ]
    var items: [ReminderItem] = [
        .init(id: "undated", title: "No due date", listID: "writable", isCompleted: false, dueDate: nil, hasDueTime: false, allowsChanges: true),
        .init(id: "done", title: "Completed", listID: "writable", isCompleted: true, dueDate: nil, hasDueTime: false, allowsChanges: true),
        .init(id: "shared", title: "Shared item", listID: "read-only", isCompleted: false, dueDate: nil, hasDueTime: false, allowsChanges: false)
    ]

    func requestAccess() async throws -> Bool {
        requestedAccess = true
        requestCount += 1
        if failRequest { throw ReminderServiceError.accessRequired }
        if waitForRequest {
            return try await withCheckedThrowingContinuation { permissionContinuation = $0 }
        }
        access = accessAfterRequest
        return requestResult
    }
    func snapshot(includeCompleted: Bool) async throws -> ReminderSnapshot {
        fetchCount += 1
        return ReminderSnapshot(lists: lists, reminders: items.filter { includeCompleted || !$0.isCompleted }, defaultListID: "read-only")
    }
    func create(title: String, listID: String, dueDate: Date?, includesTime: Bool) throws {
        if failCreate { throw ReminderServiceError.listUnavailable }
        savedTitles.append(title)
        items.append(.init(id: UUID().uuidString, title: title, listID: listID, isCompleted: false,
                           dueDate: dueDate, hasDueTime: dueDate != nil && includesTime, allowsChanges: true))
    }
    func setCompleted(id: String, completed: Bool) throws {
        if failCompletion { throw ReminderServiceError.readOnly }
        completedIDs.append(id)
        items = items.map {
            $0.id == id
                ? ReminderItem(id: $0.id, title: $0.title, listID: $0.listID, isCompleted: completed,
                               dueDate: $0.dueDate, hasDueTime: $0.hasDueTime, allowsChanges: $0.allowsChanges,
                               completionDate: completed ? Date() : nil)
                : $0
        }
    }
}

@main
private struct RemindersRegression {
    @MainActor
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "RemindersRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Phoenix")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15))!
        let dateOnly = ReminderPolicy.dueComponents(for: morning, includesTime: false, calendar: calendar)
        let timed = ReminderPolicy.dueComponents(for: morning, includesTime: true, calendar: calendar)
        try require(dateOnly.hour == nil && dateOnly.minute == nil && dateOnly.timeZone == nil, "Date-only reminders acquired a time or time zone")
        try require(dateOnly.year == 2026 && dateOnly.month == 11 && dateOnly.day == 12, "Date-only components changed the local day")
        try require(timed.hour == 9 && timed.timeZone == calendar.timeZone, "Timed reminder lost its local time zone")

        let allDay = ReminderItem(id: "date", title: "Today", listID: "writable", isCompleted: false,
                                  dueDate: morning, hasDueTime: false, allowsChanges: true)
        let atTime = ReminderItem(id: "time", title: "This morning", listID: "writable", isCompleted: false,
                                  dueDate: morning, hasDueTime: true, allowsChanges: true)
        let undated = ReminderItem(id: "none", title: "Undated", listID: "writable", isCompleted: false,
                                   dueDate: nil, hasDueTime: false, allowsChanges: true)
        let completed = ReminderItem(id: "complete", title: "Done", listID: "writable", isCompleted: true,
                                     dueDate: morning, hasDueTime: true, allowsChanges: true, completionDate: afternoon)
        let olderCompleted = ReminderItem(id: "older-complete", title: "Older", listID: "writable", isCompleted: true,
                                          dueDate: nil, hasDueTime: false, allowsChanges: true, completionDate: morning)
        try require(!allDay.isOverdue(at: afternoon, calendar: calendar), "Today's date-only reminder became overdue before the day ended")
        try require(atTime.isOverdue(at: afternoon, calendar: calendar), "Past timed reminder was not overdue")
        try require(!undated.isOverdue(at: afternoon, calendar: calendar) && !completed.isOverdue(at: afternoon, calendar: calendar), "Undated/completed reminder marked overdue")
        let sorted = ReminderPolicy.sorted([olderCompleted, completed, undated, atTime])
        try require(sorted.map(\.id) == ["time", "none", "complete", "older-complete"],
                    "Sorting lost open reminders or did not put newest completions first")

        let service = FakeRemindersService()
        let manager = RemindersManager(service: service)
        await manager.refresh()
        try require(manager.visibleReminders.contains(where: { $0.id == "undated" }), "Undated reminders are missing")
        try require(!manager.visibleReminders.contains(where: { $0.isCompleted }), "Completed reminders appeared by default")
        try require(manager.preferredCreationListID == "writable", "A read-only default list was selected for creation")
        manager.selectedListID = "read-only"
        try require(manager.visibleReminders.count == 1 && manager.visibleReminders.first?.id == "shared", "List filter was ignored")
        try require(manager.preferredCreationListID == "writable", "Read-only selected list was used for creation")
        manager.selectedListID = nil
        manager.showCompleted = true
        await manager.refresh()
        try require(manager.visibleReminders.contains(where: { $0.id == "done" }), "Show completed did not fetch completed reminders")
        manager.showCompleted = false
        await manager.refresh()
        let item = manager.reminders.first(where: { $0.id == "undated" })!
        service.failCompletion = true
        await manager.setCompleted(item, completed: true)
        try require(manager.pendingIDs.isEmpty, "Failed completion left its row permanently busy")
        try require(manager.errorMessage != nil && manager.reminders.contains(where: { $0.id == item.id && !$0.isCompleted }), "Failed save hid the reminder")
        service.failCompletion = false
        await manager.setCompleted(item, completed: true)
        try require(!manager.visibleReminders.contains(where: { $0.id == item.id }), "Successful completion did not refresh the list")
        try require(manager.reminders.contains(where: { $0.id == item.id && $0.isCompleted && $0.completionDate != nil }),
                    "Successful completion disappeared before the Done section could display it")
        manager.showCompleted = true
        await manager.refresh()
        try require(manager.visibleReminders.contains(where: { $0.id == item.id && $0.isCompleted }),
                    "Completed todo did not appear after switching to Done")
        manager.showCompleted = false
        await manager.refresh()
        service.failCreate = true
        let failed = await manager.create(title: "Draft", listID: "writable", dueDate: nil, includesTime: false)
        try require(!failed && !manager.isSaving && manager.errorMessage != nil, "Failed creation did not reset busy/error state")
        service.failCreate = false
        let created = await manager.create(title: "Created", listID: "writable", dueDate: afternoon, includesTime: true)
        try require(created && service.savedTitles == ["Created"], "Creation did not reach the service")
        try require(manager.visibleReminders.contains(where: { $0.title == "Created" && $0.dueDate == afternoon }), "Creation did not refresh saved due date")

        let fetches = service.fetchCount
        service.access = .denied
        await manager.refresh()
        try require(service.fetchCount == fetches && manager.reminders.isEmpty && manager.lists.isEmpty, "Revoked permission leaked cached reminders or fetched without access")
        await manager.requestAccess()
        try require(service.requestedAccess && manager.access == .authorized && !manager.isRequestingAccess, "Permission request did not reload the authorized state")
        // A refusal that leaves TCC undetermined must not silently redisplay Allow.
        service.access = .notDetermined
        service.requestResult = false
        service.accessAfterRequest = .notDetermined
        await manager.requestAccess()
        try require(manager.access == .notDetermined && manager.errorMessage != nil && !manager.isRequestingAccess,
                    "Undetermined refusal returned silently or left the button busy")
        service.accessAfterRequest = .denied
        await manager.requestAccess()
        try require(manager.access == .denied && manager.errorMessage != nil && manager.reminders.isEmpty,
                    "Denied access was not surfaced or kept stale reminders")
        service.access = .notDetermined
        service.failRequest = true
        await manager.requestAccess()
        try require(!manager.isRequestingAccess && manager.errorMessage != nil, "Permission error left its spinner active")
        service.failRequest = false

        let pendingService = FakeRemindersService()
        pendingService.access = .notDetermined
        pendingService.waitForRequest = true
        let pendingManager = RemindersManager(service: pendingService, permissionHelpDelayNanoseconds: 1)
        let request = Task { @MainActor in await pendingManager.requestAccess() }
        for _ in 0..<100 where pendingService.permissionContinuation == nil { await Task.yield() }
        try require(pendingService.permissionContinuation != nil && pendingManager.isRequestingAccess,
                    "Pending native request was not marked busy")
        await pendingManager.requestAccess()
        try require(pendingService.requestCount == 1, "Repeated taps launched overlapping permission dialogs")
        try await Task.sleep(nanoseconds: 5_000_000)
        try require(pendingManager.permissionNeedsAttention && pendingManager.isRequestingAccess,
                    "Slow dialog did not offer help or was falsely cancelled")
        pendingService.access = .authorized
        await pendingManager.refresh()
        try require(pendingManager.access == .authorized && !pendingManager.isRequestingAccess && !pendingManager.permissionNeedsAttention,
                    "Manual recheck did not resolve the pending request")
        pendingService.permissionContinuation?.resume(returning: false)
        await request.value
        try require(pendingManager.access == .authorized && pendingManager.errorMessage == nil,
                    "Late refusal overwrote the manually refreshed permission")
        print("Reminders policy and fake-service checks passed")
    }
}
