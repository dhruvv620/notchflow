// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SQLite3

/// Reads delivered notifications from macOS Notification Center's own store.
///
/// The store is an SQLite database in a protected container, so reading it
/// needs Full Disk Access. It is never opened in place: each read copies the
/// database and its write-ahead log into a private temporary folder and opens
/// that copy, so Notification Center is never locked or written to.
final class NotificationCenterDatabase: @unchecked Sendable {
    enum ReadError: Error, Equatable {
        /// No database was found at any known location.
        case notFound
        /// The file exists but cannot be read: Full Disk Access is missing.
        case permissionDenied
        /// The database opened but does not have the expected tables.
        case unsupportedLayout(String)
        case sqlite(String)
    }

    struct Batch: Sendable {
        let records: [NotificationCenterRecord]
        /// Highest record id in the database, read or not.
        let latestRecordID: Int64
    }

    private let queue = DispatchQueue(label: "com.dhruvv620.NotchFlow.notification-center-db", qos: .utility)
    private var lastSignature: String?
    private var lastLatestID: Int64 = 0

    /// Known locations, newest macOS first.
    static var candidateURLs: [URL] {
        var urls: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db"))
        if let darwinUserDir = darwinUserDirectory() {
            urls.append(darwinUserDir.appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }
        return urls
    }

    private static func darwinUserDirectory() -> URL? {
        let capacity = Int(PATH_MAX)
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = confstr(_CS_DARWIN_USER_DIR, &buffer, capacity)
        guard length > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    /// The database that exists, whether or not it is readable.
    static func locate() -> URL? {
        candidateURLs.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Records newer than `afterRecordID`, newest first, at most `limit`.
    /// Returns nil when nothing changed on disk since the last call.
    func read(afterRecordID: Int64, limit: Int, force: Bool = false) async throws -> Batch? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Batch?, Error>) in
            queue.async {
                do {
                    continuation.resume(returning: try self.readOnQueue(afterRecordID: afterRecordID, limit: limit, force: force))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func reset() {
        queue.async {
            self.lastSignature = nil
            self.lastLatestID = 0
        }
    }

    private func readOnQueue(afterRecordID: Int64, limit: Int, force: Bool) throws -> Batch? {
        guard let source = Self.locate() else { throw ReadError.notFound }
        // POSIX permissions say the file is readable; privacy protection
        // (Full Disk Access) only shows when actually opening it.
        guard let probe = try? FileHandle(forReadingFrom: source) else {
            throw ReadError.permissionDenied
        }
        try? probe.close()

        // Skip the copy when neither the database nor its log has changed.
        let signature = Self.signature(of: source)
        if !force, signature == lastSignature, afterRecordID >= lastLatestID {
            return nil
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlow-NotificationCenter-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }

        let copy = folder.appendingPathComponent("db")
        do {
            try FileManager.default.copyItem(at: source, to: copy)
        } catch {
            throw ReadError.permissionDenied
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try? FileManager.default.copyItem(at: sidecar, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var handle: OpaquePointer?
        // The copy is ours, so it may be opened for writing: SQLite needs that
        // to apply the copied write-ahead log.
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw ReadError.sqlite(message)
        }
        defer { sqlite3_close(db) }

        let recordColumns = try columns(of: "record", in: db)
        let appColumns = try columns(of: "app", in: db)
        guard recordColumns.contains("rec_id"), recordColumns.contains("data"), recordColumns.contains("app_id") else {
            throw ReadError.unsupportedLayout("record table has \(recordColumns.sorted().joined(separator: ", "))")
        }
        let hasAppTable = appColumns.contains("app_id") && appColumns.contains("identifier")
        let dateColumn = ["delivered_date", "request_date", "request_last_date"].first { recordColumns.contains($0) }

        let latestID = try scalarInt64("SELECT IFNULL(MAX(rec_id), 0) FROM record", in: db)
        let appSelect = hasAppTable ? "a.identifier" : "NULL"
        let join = hasAppTable ? "LEFT JOIN app a ON a.app_id = r.app_id" : ""
        let dateSelect = dateColumn.map { "r.\($0)" } ?? "NULL"
        let sql = """
            SELECT r.rec_id, \(appSelect), r.data, \(dateSelect)
            FROM record r \(join)
            WHERE r.rec_id > ?
            ORDER BY r.rec_id DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, afterRecordID)
        sqlite3_bind_int64(statement, 2, Int64(max(1, limit)))

        var records: [NotificationCenterRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recordID = sqlite3_column_int64(statement, 0)
            let app = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let length = Int(sqlite3_column_bytes(statement, 2))
            guard length > 0, let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: length)
            let fallback: Date? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            if let record = NotificationCenterRecord.parse(recordID: recordID, appIdentifier: app, data: data, fallbackDate: fallback) {
                records.append(record)
            }
        }

        lastSignature = signature
        lastLatestID = latestID
        return Batch(records: records, latestRecordID: latestID)
    }

    private static func signature(of url: URL) -> String {
        [url.path, url.path + "-wal"].map { path -> String in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(size)@\(modified)"
        }.joined(separator: "|")
    }

    private func columns(of table: String, in db: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }

    private func scalarInt64(_ sql: String, in db: OpaquePointer) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
    }
}
