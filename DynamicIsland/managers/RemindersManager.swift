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
    @Published private(set) var isSaving = false
    @Published private(set) var pendingIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var selectedListID: String?
    @Published var showCompleted = false
    private let service: RemindersServiceProviding
    private var refreshID = UUID()
    private var defaultListID: String?

    init(service: RemindersServiceProviding) {
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
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        errorMessage = nil
        do {
            _ = try await service.requestAccess()
            await refresh()
        } catch {
            access = service.access
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        let id = UUID()
        refreshID = id
        access = service.access
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
