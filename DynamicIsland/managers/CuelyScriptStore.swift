// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

/// Main-actor adapter used by SwiftUI. Persistence errors stay visible instead
/// of being swallowed, while validation remains shared with regression tests.
@MainActor
final class CuelyScriptStore: ObservableObject {
    static let shared = CuelyScriptStore()

    @Published private(set) var scripts: [CuelyScript] = []
    @Published var errorMessage: String?

    private let persistence: CuelyScriptPersistence

    init(persistence: CuelyScriptPersistence = CuelyScriptPersistence()) {
        self.persistence = persistence
        reload()
    }

    func reload() {
        do {
            scripts = try persistence.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(title: String, text: String) -> CuelyScript? {
        perform { try persistence.create(title: title, text: text) }
    }

    @discardableResult
    func update(id: UUID, title: String, text: String) -> CuelyScript? {
        perform { try persistence.update(id: id, title: title, text: text) }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        perform {
            try persistence.delete(id: id)
            return true
        } ?? false
    }

    @discardableResult
    func duplicate(id: UUID) -> CuelyScript? {
        perform { try persistence.duplicate(id: id) }
    }

    @discardableResult
    func move(id: UUID, to destinationIndex: Int) -> Bool {
        perform {
            try persistence.move(id: id, to: destinationIndex)
            return true
        } ?? false
    }

    private func perform<Value>(_ mutation: () throws -> Value) -> Value? {
        do {
            let result = try mutation()
            scripts = persistence.scripts
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
