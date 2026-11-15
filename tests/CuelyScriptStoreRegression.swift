// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

private struct LegacyCuelyScriptFixture: Encodable {
    let id: UUID
    let title: String
    let text: String
}

private struct VersionedCuelyScriptFixture: Encodable {
    let version: Int
    let scripts: [CuelyScript]
}

private struct InvalidTimestampCuelyScriptFixture: Encodable {
    let id: UUID
    let title: String
    let text: String
    let createdAt: Date
    let updatedAt: Date
}

private struct InvalidTimestampPayloadFixture: Encodable {
    let version: Int
    let scripts: [InvalidTimestampCuelyScriptFixture]
}

@main
enum CuelyScriptStoreRegression {
    static func main() throws {
        func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            let succeeded = try condition()
            if !succeeded {
                throw NSError(domain: "CuelyScriptStoreRegression", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NotchFlow-Cuely-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("scripts.json")
        let store = CuelyScriptPersistence(fileURL: file, fileManager: fileManager)

        try require(try store.load().isEmpty, "A missing library did not start empty")
        do {
            _ = try store.create(title: "   ", text: "Text")
            throw NSError(domain: "CuelyScriptStoreRegression", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Blank title was accepted"])
        } catch CuelyScriptValidationError.emptyTitle {}
        do {
            _ = try store.create(title: "Title", text: "\n\t")
            throw NSError(domain: "CuelyScriptStoreRegression", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Blank text was accepted"])
        } catch CuelyScriptValidationError.emptyText {}
        do {
            _ = try store.create(
                title: String(repeating: "T", count: CuelyScriptPolicy.maximumTitleLength + 1),
                text: "Text"
            )
            throw NSError(domain: "CuelyScriptStoreRegression", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Oversized title was accepted"])
        } catch CuelyScriptValidationError.titleTooLong {}
        do {
            _ = try store.create(
                title: "Title",
                text: String(repeating: "T", count: CuelyScriptPolicy.maximumTextLength + 1)
            )
            throw NSError(domain: "CuelyScriptStoreRegression", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Oversized text was accepted"])
        } catch CuelyScriptValidationError.textTooLong {}

        let firstDate = Date(timeIntervalSince1970: 1_000)
        let clampedDate = CuelyScript(title: "Clock", text: "Clock", createdAt: firstDate,
                                      updatedAt: Date(timeIntervalSince1970: 500))
        try require(clampedDate.updatedAt == firstDate,
                    "A directly constructed script allowed an update before its creation")
        let first = try store.create(title: "  Launch script  ", text: "First\r\nSecond", now: firstDate)
        try require(first.title == "Launch script", "Title whitespace was not normalized")
        try require(first.text == "First\nSecond", "Pasted line endings were not normalized")
        try require(store.scripts.map(\.id) == [first.id], "Created script was not stored")

        let reloaded = CuelyScriptPersistence(fileURL: file, fileManager: fileManager)
        try require(try reloaded.load() == [first], "Atomic save did not survive reload")
        let updated = try reloaded.update(id: first.id, title: "Launch update", text: "Revised",
                                          now: Date(timeIntervalSince1970: 2_000))
        try require(updated.createdAt == firstDate && updated.updatedAt > firstDate,
                    "Editing did not preserve creation time or advance update time")
        let afterClockCorrection = try reloaded.update(
            id: first.id, title: "Launch update", text: "Still revised",
            now: Date(timeIntervalSince1970: 1_500)
        )
        try require(afterClockCorrection.updatedAt == updated.updatedAt,
                    "A backward wall-clock correction regressed the saved update date")

        let second = try reloaded.create(title: "Second", text: "Another script",
                                         now: Date(timeIntervalSince1970: 3_000))
        try require(reloaded.scripts.map(\.id) == [second.id, first.id],
                    "New scripts were not placed first")
        try reloaded.move(id: second.id, to: 99)
        try require(reloaded.scripts.map(\.id) == [first.id, second.id],
                    "Reordering did not clamp to the final position")
        let copy = try reloaded.duplicate(id: first.id, now: Date(timeIntervalSince1970: 4_000))
        try require(copy.title == "Launch update Copy" && copy.text == afterClockCorrection.text,
                    "Duplication did not preserve content with a distinct title")
        try reloaded.delete(id: first.id)
        try require(!reloaded.scripts.contains(where: { $0.id == first.id }), "Deletion did not persist")
        let finalReload = CuelyScriptPersistence(fileURL: file, fileManager: fileManager)
        try require(try finalReload.load().map(\.id) == reloaded.scripts.map(\.id),
                    "Reorder/delete order did not survive reload")

        let orderingFile = root.appendingPathComponent("ordering.json")
        let ordering = CuelyScriptPersistence(fileURL: orderingFile, fileManager: fileManager)
        let a = try ordering.create(title: "A", text: "A")
        let b = try ordering.create(title: "B", text: "B")
        let c = try ordering.create(title: "C", text: "C")
        try require(ordering.scripts.map(\.id) == [c.id, b.id, a.id],
                    "Setup order was not newest first")
        try ordering.move(id: c.id, to: 1)
        try require(ordering.scripts.map(\.id) == [b.id, c.id, a.id],
                    "Moving down did not use a final destination index")
        try ordering.move(id: a.id, to: 0)
        try require(ordering.scripts.map(\.id) == [a.id, b.id, c.id],
                    "Moving up did not use a final destination index")

        // A blocked parent path makes the atomic commit fail. In-memory state
        // must remain unchanged so the UI never displays an unsaved script.
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blocker)
        let failing = CuelyScriptPersistence(fileURL: blocker.appendingPathComponent("scripts.json"),
                                             fileManager: fileManager)
        do {
            _ = try failing.create(title: "Unsaved", text: "Must roll back")
            throw NSError(domain: "CuelyScriptStoreRegression", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Blocked write unexpectedly succeeded"])
        } catch {
            try require(failing.scripts.isEmpty, "Failed write changed in-memory scripts")
        }

        let updateFailureFile = root.appendingPathComponent("update-failure.json")
        let updateFailure = CuelyScriptPersistence(fileURL: updateFailureFile, fileManager: fileManager)
        let beforeFailedUpdate = try updateFailure.create(title: "Original", text: "Original")
        try fileManager.removeItem(at: updateFailureFile)
        try fileManager.createDirectory(at: updateFailureFile, withIntermediateDirectories: false)
        do {
            _ = try updateFailure.update(id: beforeFailedUpdate.id, title: "Changed", text: "Changed")
            throw NSError(domain: "CuelyScriptStoreRegression", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Blocked update unexpectedly succeeded"])
        } catch {
            try require(updateFailure.scripts == [beforeFailedUpdate],
                        "Failed update changed the last committed in-memory script")
        }

        // Migrate the bare id/title/text array written by the rejected Cuely
        // experiment, preserving both content and ordering.
        let legacyFile = root.appendingPathComponent("legacy.json")
        let legacyID = UUID()
        let legacyData = try JSONEncoder().encode([
            LegacyCuelyScriptFixture(id: legacyID, title: "  Old script  ", text: "Keep\r\nthis text")
        ])
        try legacyData.write(to: legacyFile)
        let legacyStore = CuelyScriptPersistence(fileURL: legacyFile, fileManager: fileManager)
        let migrated = try legacyStore.load()
        try require(migrated.map(\.id) == [legacyID]
                    && migrated[0].title == "Old script"
                    && migrated[0].text == "Keep\nthis text",
                    "Legacy Cuely scripts were not migrated")
        let migratedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyFile)) as? [String: Any]
        try require(migratedJSON?["version"] as? Int == CuelyScriptPersistence.currentVersion,
                    "Legacy migration did not rewrite the versioned payload")

        // A failed reload must keep the last known-good in-memory library.
        let corruptFile = root.appendingPathComponent("corrupt.json")
        let corruptStore = CuelyScriptPersistence(fileURL: corruptFile, fileManager: fileManager)
        let retained = try corruptStore.create(title: "Retained", text: "Last good copy")
        try Data("{".utf8).write(to: corruptFile)
        var rejectedCorruption = false
        do {
            _ = try corruptStore.load()
        } catch {
            rejectedCorruption = true
        }
        try require(rejectedCorruption, "Corrupt JSON unexpectedly loaded")
        try require(corruptStore.scripts.map(\.id) == [retained.id],
                    "A corrupt reload discarded the last known-good scripts")
        let corruptBytes = try Data(contentsOf: corruptFile)
        do {
            _ = try corruptStore.create(title: "Do not overwrite", text: "Blocked")
            throw NSError(domain: "CuelyScriptStoreRegression", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Mutation after corrupt load succeeded"])
        } catch CuelyScriptStoreError.libraryUnavailable {}
        try require(try Data(contentsOf: corruptFile) == corruptBytes,
                    "A mutation after corrupt load overwrote the recoverable file")
        try fileManager.removeItem(at: corruptFile)
        try require(try corruptStore.load().isEmpty,
                    "A successful reload did not recover from the corruption guard")
        _ = try corruptStore.create(title: "Recovered", text: "Writable after reload")

        let unsupportedFile = root.appendingPathComponent("unsupported.json")
        try Data("{\"version\":2,\"scripts\":[]}".utf8).write(to: unsupportedFile)
        let unsupported = CuelyScriptPersistence(fileURL: unsupportedFile, fileManager: fileManager)
        do {
            _ = try unsupported.load()
            throw NSError(domain: "CuelyScriptStoreRegression", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported version loaded"])
        } catch CuelyScriptStoreError.unsupportedVersion(2) {}
        do {
            _ = try unsupported.create(title: "Do not downgrade", text: "Blocked")
            throw NSError(domain: "CuelyScriptStoreRegression", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported file was overwritten"])
        } catch CuelyScriptStoreError.libraryUnavailable {}

        let duplicateFile = root.appendingPathComponent("duplicate.json")
        let duplicateID = UUID()
        let duplicateDate = Date(timeIntervalSince1970: 10_000)
        let duplicateScript = CuelyScript(id: duplicateID, title: "Duplicate", text: "Duplicate",
                                          createdAt: duplicateDate)
        let duplicatePayload = VersionedCuelyScriptFixture(
            version: CuelyScriptPersistence.currentVersion,
            scripts: [duplicateScript, duplicateScript]
        )
        try JSONEncoder().encode(duplicatePayload).write(to: duplicateFile)
        let duplicateStore = CuelyScriptPersistence(fileURL: duplicateFile, fileManager: fileManager)
        do {
            _ = try duplicateStore.load()
            throw NSError(domain: "CuelyScriptStoreRegression", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Duplicate identifiers loaded"])
        } catch CuelyScriptStoreError.duplicateIdentifier {}

        let timestampFile = root.appendingPathComponent("invalid-timestamp.json")
        let invalidTimestampScript = InvalidTimestampCuelyScriptFixture(
            id: UUID(),
            title: "Invalid date",
            text: "Reject this payload",
            createdAt: Date(timeIntervalSince1970: 20_000),
            updatedAt: Date(timeIntervalSince1970: 10_000)
        )
        try JSONEncoder().encode(
            InvalidTimestampPayloadFixture(
                version: CuelyScriptPersistence.currentVersion,
                scripts: [invalidTimestampScript]
            )
        ).write(to: timestampFile)
        let timestampStore = CuelyScriptPersistence(fileURL: timestampFile, fileManager: fileManager)
        do {
            _ = try timestampStore.load()
            throw NSError(domain: "CuelyScriptStoreRegression", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid timestamps loaded"])
        } catch CuelyScriptStoreError.invalidTimestamps {}

        print("Cuely script validation, persistence, rollback and ordering checks passed")
    }
}
