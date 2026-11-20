// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// A message from the Messages app's history (iMessage and SMS), for the
/// promise keeper.
struct MessagesHistoryMessage: Equatable, Sendable {
    let rowID: Int64
    let text: String
    let fromMe: Bool
    let date: Date
    /// The chat's id ("iMessage;-;+15551234567"), which AppleScript accepts as `chat id`.
    let chatGUID: String
    /// The other person's phone number or email (1:1 chats).
    let handle: String
    /// A group's name, if it has one.
    let groupName: String
    /// The other side's message just before this one, if recent.
    let replyingTo: String?
}

/// Reading the Messages database (Foundation only, so Build.command can check it alone).
enum MessagesHistoryPolicy {
    /// Messages stores dates as seconds, or (since macOS 10.13) nanoseconds,
    /// since 1 January 2001.
    static func date(fromAppleTime value: Int64) -> Date {
        let seconds = value > 100_000_000_000 ? Double(value) / 1_000_000_000 : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// The plain text of a message's `attributedBody` (an archived
    /// NSAttributedString, which newer macOS stores instead of `text`). Reads
    /// the string's bytes directly, without unarchiving objects.
    static func text(fromAttributedBody data: Data) -> String? {
        let bytes = [UInt8](data)
        let marker = Array("NSString".utf8)
        guard let start = firstIndex(of: marker, in: bytes) else { return nil }
        // After the class name: a few bytes of type information, ending with "+".
        var index = start + marker.count
        let limit = min(bytes.count, index + 12)
        while index < limit, bytes[index] != 0x2B { index += 1 }
        guard index < bytes.count, bytes[index] == 0x2B else { return nil }
        index += 1
        guard index < bytes.count else { return nil }
        var length = Int(bytes[index])
        index += 1
        if length == 0x81 {
            guard index + 2 <= bytes.count else { return nil }
            length = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            index += 2
        } else if length == 0x82 {
            guard index + 4 <= bytes.count else { return nil }
            length = Int(bytes[index]) | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2]) << 16 | Int(bytes[index + 3]) << 24
            index += 4
        }
        guard length > 0, index + length <= bytes.count else { return nil }
        let text = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
            if Array(haystack[start..<(start + needle.count)]) == needle { return start }
        }
        return nil
    }

    /// Message text, cleaned of the object-replacement characters Messages
    /// puts where attachments are.
    static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
