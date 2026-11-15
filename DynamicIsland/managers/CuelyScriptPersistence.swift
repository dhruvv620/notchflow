// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum CuelyScriptStoreError: LocalizedError, Equatable, Sendable {
    case scriptNotFound
    case duplicateIdentifier
    case invalidTimestamps
    case libraryUnavailable
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "That script is no longer available."
        case .duplicateIdentifier:
            return "The saved script file contains duplicate identifiers."
        case .invalidTimestamps:
            return "The saved script file contains invalid dates."
        case .libraryUnavailable:
            return "Scripts cannot be changed until the saved script file loads successfully."
        case .unsupportedVersion(let version):
            return "This saved script file uses unsupported version \(version)."
        }
    }
}

/// Pure-Foundation script persistence. Mutations are committed to disk before
/// the in-memory array changes, so a failed write never appears saved in the UI.
final class CuelyScriptPersistence {
    private struct Payload: Codable {
        let version: Int
        let scripts: [CuelyScript]
    }

    /// The rejected experimental Cuely build wrote a bare array containing
    /// only these fields. Accept it once so reinstalling the fresh build does
    /// not strand scripts the user already wrote.
    private struct LegacyScript: Decodable {
        let id: UUID
        let title: String
        let text: String
    }

    static let currentVersion = 1

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var mutationsBlocked = false
    private(set) var scripts: [CuelyScript] = []

    init(fileURL: URL = CuelyScriptPersistence.defaultFileURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchFlow/Cuely", isDirectory: true)
            .appendingPathComponent("scripts.json", isDirectory: false)
    }

    @discardableResult
    func load() throws -> [CuelyScript] {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                scripts = []
                mutationsBlocked = false
                return scripts
            }
            let data = try Data(contentsOf: fileURL)
            let payload: Payload
            do {
                payload = try decoder.decode(Payload.self, from: data)
            } catch let payloadError {
                guard let legacy = try? decoder.decode([LegacyScript].self, from: data) else {
                    throw payloadError
                }
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let migrationDate = attributes?[.modificationDate] as? Date ?? Date()
                let migrated = try canonicalized(legacy.map {
                    CuelyScript(id: $0.id, title: $0.title, text: $0.text,
                                createdAt: migrationDate, updatedAt: migrationDate)
                })
                try persist(migrated)
                scripts = migrated
                mutationsBlocked = false
                return scripts
            }

            guard payload.version == Self.currentVersion else {
                throw CuelyScriptStoreError.unsupportedVersion(payload.version)
            }
            let loaded = try canonicalized(payload.scripts)
            // Keep the on-disk representation canonical even if an older build
            // or a hand edit left surrounding title whitespace or CR line ends.
            if loaded != payload.scripts {
                try persist(loaded)
            }
            scripts = loaded
            mutationsBlocked = false
            return scripts
        } catch {
            // Do not let an empty UI overwrite a newer/unsupported or corrupt
            // file. A later successful reload clears this guard.
            mutationsBlocked = true
            throw error
        }
    }

    @discardableResult
    func create(title: String, text: String, now: Date = Date()) throws -> CuelyScript {
        let content = try CuelyScriptPolicy.validated(title: title, text: text)
        let script = CuelyScript(title: content.title, text: content.text, createdAt: now)
        var next = scripts
        next.insert(script, at: 0)
        try commit(next)
        return script
    }

    @discardableResult
    func update(id: UUID, title: String, text: String, now: Date = Date()) throws -> CuelyScript {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else {
            throw CuelyScriptStoreError.scriptNotFound
        }
        let content = try CuelyScriptPolicy.validated(title: title, text: text)
        var next = scripts
        next[index].title = content.title
        next[index].text = content.text
        // A wall-clock correction must never make an edited script look older
        // than its previous saved revision.
        next[index].updatedAt = max(next[index].updatedAt, max(now, next[index].createdAt))
        try commit(next)
        return next[index]
    }

    @discardableResult
    func duplicate(id: UUID, now: Date = Date()) throws -> CuelyScript {
        guard let source = scripts.first(where: { $0.id == id }) else {
            throw CuelyScriptStoreError.scriptNotFound
        }
        return try create(title: CuelyScriptPolicy.duplicateTitle(source.title), text: source.text, now: now)
    }

    func delete(id: UUID) throws {
        guard scripts.contains(where: { $0.id == id }) else {
            throw CuelyScriptStoreError.scriptNotFound
        }
        try commit(scripts.filter { $0.id != id })
    }

    /// Moves one script to a final zero-based index. Out-of-range destinations
    /// are clamped so a refresh during drag/drop cannot produce an invalid write.
    func move(id: UUID, to destinationIndex: Int) throws {
        guard let sourceIndex = scripts.firstIndex(where: { $0.id == id }) else {
            throw CuelyScriptStoreError.scriptNotFound
        }
        var next = scripts
        let item = next.remove(at: sourceIndex)
        next.insert(item, at: min(max(0, destinationIndex), next.count))
        try commit(next)
    }

    private func canonicalized(_ loaded: [CuelyScript]) throws -> [CuelyScript] {
        guard Set(loaded.map(\.id)).count == loaded.count else {
            throw CuelyScriptStoreError.duplicateIdentifier
        }
        return try loaded.map { script in
            guard script.updatedAt >= script.createdAt else {
                throw CuelyScriptStoreError.invalidTimestamps
            }
            let content = try CuelyScriptPolicy.validated(title: script.title, text: script.text)
            var canonical = script
            canonical.title = content.title
            canonical.text = content.text
            return canonical
        }
    }

    private func commit(_ next: [CuelyScript]) throws {
        guard !mutationsBlocked else {
            throw CuelyScriptStoreError.libraryUnavailable
        }
        try persist(next)
        scripts = next
    }

    private func persist(_ next: [CuelyScript]) throws {
        let data = try encoder.encode(Payload(version: Self.currentVersion, scripts: next))
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
