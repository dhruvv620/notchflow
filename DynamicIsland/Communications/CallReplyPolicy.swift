// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Quick replies for declining a call, and how they are addressed.
///
/// Pure logic (Foundation only), so Build.command can check it alone.
enum CallReplyPolicy {
    static let presets: [String] = [
        "Can't talk now. I'll call you back.",
        "In a meeting. I'll call you after.",
        "On my way.",
        "Call you in 5 minutes.",
    ]

    /// Whether the caller label is itself a phone number or email address.
    static func directHandle(from caller: String) -> String? {
        let trimmed = caller.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@"), trimmed.contains("."), !trimmed.contains(" ") { return trimmed }
        let digits = trimmed.filter { $0.isNumber }
        let allowed = Set("0123456789+()- .")
        guard digits.count >= 6, trimmed.allSatisfy({ allowed.contains($0) }) else { return nil }
        return (trimmed.hasPrefix("+") ? "+" : "") + digits
    }

    /// Initials for an avatar: "Selene Park" -> "SP", "+1 555" -> "#".
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
            .filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "#" : letters.joined()
    }

    /// A stable hue for a name, so the same caller always gets the same color.
    static func hue(for name: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in name.lowercased().utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Double(hash % 360) / 360
    }

    /// AppleScript that sends `text` to a phone number or email in Messages.
    static func messagesScript(text: String, handle: String) -> String {
        """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant \(NotchNotificationPolicy.appleScriptString(handle)) of targetService
            send \(NotchNotificationPolicy.appleScriptString(text)) to targetBuddy
        end tell
        """
    }

    /// Whether a notification is from the caller: the same name heads it.
    static func isFromCaller(caller: String, headline: String) -> Bool {
        let name = caller.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = headline.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !title.isEmpty else { return false }
        return title == name || title.hasPrefix(name + " ") || title.hasPrefix(name + " ·")
    }
}
