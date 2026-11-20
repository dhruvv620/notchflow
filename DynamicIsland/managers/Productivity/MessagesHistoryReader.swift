// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation
import SQLite3

extension Defaults.Keys {
    /// Read messages you send in Messages (needs Full Disk Access), so
    /// promises and agreed plans made there are kept too.
    static let promiseReadMessagesHistory = Key<Bool>("promiseReadMessagesHistory", default: true)
    /// The newest Messages row already looked at.
    static let messagesHistoryLastRowID = Key<Int>("messagesHistoryLastRowID", default: 0)
}

/// Reads new messages from the Messages app's database (`~/Library/Messages/chat.db`),
/// which needs Full Disk Access. Like the Notification Center reader, it never
/// opens the database in place: each read copies it (and its write-ahead log)
/// into a private temporary folder. Only messages newer than the last read
/// are looked at, never your history.
final class MessagesHistoryReader: @unchecked Sendable {
    enum ReadError: Error { case notFound, permissionDenied, sqlite(String) }

    private let queue = DispatchQueue(label: "com.dhruvv620.NotchFlow.messages-history", qos: .utility)
    private var lastSignature: String?

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
    }

    /// Messages after `afterRowID`, oldest first, and the newest row id. With
    /// `afterRowID` 0 (the first read) none are returned: reading starts now.
    func read(afterRowID: Int64) async throws -> (messages: [MessagesHistoryMessage], latestRowID: Int64)? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.readOnQueue(afterRowID: afterRowID)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func readOnQueue(afterRowID: Int64) throws -> (messages: [MessagesHistoryMessage], latestRowID: Int64)? {
        let source = Self.databaseURL
        guard FileManager.default.fileExists(atPath: source.path) else { throw ReadError.notFound }
        guard let probe = try? FileHandle(forReadingFrom: source) else { throw ReadError.permissionDenied }
        try? probe.close()

        let signature = [source.path, source.path + "-wal"].map { path -> String in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(size)@\(modified)"
        }.joined(separator: "|")
        if signature == lastSignature, afterRowID > 0 { return nil }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlow-Messages-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("chat.db")
        do { try FileManager.default.copyItem(at: source, to: copy) } catch { throw ReadError.permissionDenied }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try? FileManager.default.copyItem(at: sidecar, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw ReadError.sqlite(message)
        }
        defer { sqlite3_close(db) }

        let latest = scalar("SELECT IFNULL(MAX(ROWID), 0) FROM message", in: db)
        lastSignature = signature
        // The first read only notes where "now" is; rows ids reset if the database was rebuilt.
        guard afterRowID > 0, afterRowID <= latest else { return ([], latest) }

        let sql = """
            SELECT m.ROWID, m.text, m.attributedBody, m.is_from_me, m.date, IFNULL(h.id, ''),
                   IFNULL(c.guid, ''), IFNULL(c.display_name, ''), IFNULL(c.ROWID, 0)
            FROM message m
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE m.ROWID > ? AND IFNULL(m.associated_message_type, 0) = 0
            ORDER BY m.ROWID ASC
            LIMIT 60
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, afterRowID)

        var result: [MessagesHistoryMessage] = []
        var rows = 0
        var lastRow = afterRowID
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            rows += 1
            lastRow = max(lastRow, rowID)
            guard let text = Self.text(statement, textColumn: 1, bodyColumn: 2), !text.isEmpty else { continue }
            let fromMe = sqlite3_column_int(statement, 3) == 1
            let date = MessagesHistoryPolicy.date(fromAppleTime: sqlite3_column_int64(statement, 4))
            let chatGUID = Self.string(statement, 6)
            let chatRowID = sqlite3_column_int64(statement, 8)
            let previous = chatRowID > 0 ? previousMessage(in: chatRowID, before: rowID, fromMe: !fromMe, after: date, db: db) : nil
            result.append(MessagesHistoryMessage(rowID: rowID, text: text, fromMe: fromMe, date: date, chatGUID: chatGUID,
                                                 handle: Self.string(statement, 5),
                                                 groupName: Self.string(statement, 7),
                                                 replyingTo: previous))
        }
        // A full page: continue from its last row next time.
        return (result, rows >= 60 ? lastRow : latest)
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    /// The other side's last message before this one in the chat, from the last day.
    private func previousMessage(in chat: Int64, before rowID: Int64, fromMe: Bool, after date: Date, db: OpaquePointer) -> String? {
        let sql = """
            SELECT m.text, m.attributedBody, m.date FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            WHERE cmj.chat_id = ? AND m.ROWID < ? AND m.is_from_me = ? AND IFNULL(m.associated_message_type, 0) = 0
            ORDER BY m.ROWID DESC LIMIT 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, chat)
        sqlite3_bind_int64(statement, 2, rowID)
        sqlite3_bind_int(statement, 3, fromMe ? 1 : 0)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let sent = MessagesHistoryPolicy.date(fromAppleTime: sqlite3_column_int64(statement, 2))
        guard date.timeIntervalSince(sent) < 86_400 else { return nil }
        return Self.text(statement, textColumn: 0, bodyColumn: 1)
    }

    private static func text(_ statement: OpaquePointer, textColumn: Int32, bodyColumn: Int32) -> String? {
        if let raw = sqlite3_column_text(statement, textColumn) {
            let text = MessagesHistoryPolicy.cleaned(String(cString: raw))
            if !text.isEmpty { return text }
        }
        let length = Int(sqlite3_column_bytes(statement, bodyColumn))
        guard length > 0, let bytes = sqlite3_column_blob(statement, bodyColumn) else { return nil }
        return MessagesHistoryPolicy.text(fromAttributedBody: Data(bytes: bytes, count: length)).map(MessagesHistoryPolicy.cleaned)
    }

    private func scalar(_ sql: String, in db: OpaquePointer) -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
    }
}
