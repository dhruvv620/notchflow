// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

@MainActor
final class RemindersManager: ObservableObject {
    static let shared = RemindersManager(service: EventKitRemindersService())

    @Published private(set) var access: ReminderAccess
    @Published private(set) var lists: [ReminderListItem] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var permissionNeedsAttention = false
    @Published private(set) var isSaving = false
    @Published private(set) var pendingIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var selectedListID: String?
    @Published var showCompleted = false
    private let service: RemindersServiceProviding
    private var refreshID = UUID()
    private var defaultListID: String?
    private var permissionAttemptID: UUID?
    private var permissionHelpTask: Task<Void, Never>?
    private let permissionHelpDelayNanoseconds: UInt64

    init(service: RemindersServiceProviding, permissionHelpDelayNanoseconds: UInt64 = 8_000_000_000) {
        self.permissionHelpDelayNanoseconds = permissionHelpDelayNanoseconds
        self.service = service
        access = service.access
    }

    var writableLists: [ReminderListItem] { lists.filter(\.allowsChanges) }
    var visibleReminders: [ReminderItem] {
        reminders.filter {
            (selectedListID == nil || $0.listID == selectedListID)
                && (showCompleted || !$0.isCompleted)
        }
    }
    var preferredCreationListID: String? {
        if let selectedListID, writableLists.contains(where: { $0.id == selectedListID }) { return selectedListID }
        if let defaultListID, writableLists.contains(where: { $0.id == defaultListID }) { return defaultListID }
        return writableLists.first?.id
    }

    func requestAccess() async {
        guard !isRequestingAccess else { return }
        let attempt = UUID()
        permissionAttemptID = attempt
        isRequestingAccess = true
        permissionNeedsAttention = false
        errorMessage = nil
        let delay = permissionHelpDelayNanoseconds
        permissionHelpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.permissionAttemptID == attempt else { return }
            // This is help for a slow system dialog, not a denial or cancellation.
            self.permissionNeedsAttention = true
        }
        do {
            let granted = try await service.requestAccess()
            guard permissionAttemptID == attempt else { return }
            finishPermissionAttempt()
            await refresh()
            if access != .authorized {
                if access == .restricted {
                    errorMessage = String(localized: "Reminders access is restricted on this Mac.")
                } else if granted {
                    errorMessage = String(localized: "macOS has not updated Reminders access yet. Open Privacy Settings, then choose Check Access.")
                } else {
                    errorMessage = String(localized: "macOS did not grant Reminders access. Enable NotchFlow in Privacy Settings, then choose Check Access.")
                }
            }
        } catch {
            guard permissionAttemptID == attempt else { return }
            finishPermissionAttempt()
            access = service.access
            errorMessage = error.localizedDescription
        }
    }

    private func finishPermissionAttempt() {
        permissionAttemptID = nil
        permissionHelpTask?.cancel()
        permissionHelpTask = nil
        isRequestingAccess = false
        permissionNeedsAttention = false
    }

    func refresh() async {
        let id = UUID()
        refreshID = id
        access = service.access
        if permissionAttemptID != nil && access != .notDetermined {
            // A manual recheck or returning from System Settings can resolve
            // access before the original EventKit completion arrives.
            finishPermissionAttempt()
        }
        guard access == .authorized else {
            lists = []
            reminders = []
            defaultListID = nil
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let snapshot = try await service.snapshot(includeCompleted: showCompleted)
            guard id == refreshID else { return }
            lists = snapshot.lists
            reminders = snapshot.reminders
            defaultListID = snapshot.defaultListID
            if let selectedListID, !lists.contains(where: { $0.id == selectedListID }) { self.selectedListID = nil }
        } catch {
            guard id == refreshID else { return }
            access = service.access
            if access != .authorized { lists = []; reminders = [] }
            errorMessage = error.localizedDescription
        }
        if id == refreshID { isLoading = false }
    }

    @discardableResult
    func create(title: String, listID: String, dueDate: Date?, includesTime: Bool) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try service.create(title: title, listID: listID, dueDate: dueDate, includesTime: includesTime)
            await refresh()
            return true
        } catch {
            access = service.access
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setCompleted(_ item: ReminderItem, completed: Bool) async {
        guard !pendingIDs.contains(item.id) else { return }
        pendingIDs.insert(item.id)
        errorMessage = nil
        defer { pendingIDs.remove(item.id) }
        do {
            try service.setCompleted(id: item.id, completed: completed)
            await refresh()
        } catch {
            access = service.access
            errorMessage = error.localizedDescription
        }
    }
}
