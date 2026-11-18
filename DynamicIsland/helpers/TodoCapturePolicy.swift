// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Turns dropped or forwarded content into a todo title, and measures today's
/// progress. Pure logic (Foundation only), so Build.command can check it alone.
enum TodoCapturePolicy {
    static let maximumTitleLength = 180

    /// A one-line title from dropped text: the first non-empty line, with runs
    /// of whitespace collapsed and long text shortened at a word boundary.
    static func title(fromText text: String) -> String? {
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let collapsed = firstLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maximumTitleLength else { return collapsed }
        let cut = collapsed.prefix(maximumTitleLength)
        let wordBoundary = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return String(wordBoundary) + "…"
    }

    /// A title for a dropped link: "Read example.com/article" style.
    static func title(fromURL url: URL) -> String {
        if url.isFileURL {
            return "Open \(url.deletingPathExtension().lastPathComponent)"
        }
        if url.scheme == "mailto" {
            let address = url.absoluteString.dropFirst("mailto:".count).split(separator: "?").first.map(String.init) ?? ""
            return address.isEmpty ? "Send an email" : "Email \(address)"
        }
        let host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        let path = url.path == "/" ? "" : url.path
        return "Read \(host)\(path)"
    }

    /// A title for following up on a notification or message.
    static func followUpTitle(sender: String, body: String) -> String {
        let who = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = title(fromText: body) ?? ""
        let base = who.isEmpty ? "Follow up" : "Reply to \(who)"
        guard !snippet.isEmpty else { return base }
        return title(fromText: "\(base): \(snippet)") ?? base
    }

    struct Progress: Equatable, Sendable {
        let done: Int
        let total: Int
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    /// Todos due today (or overdue and still open), and how many of today's
    /// were completed today.
    static func todayProgress(
        _ items: [(isCompleted: Bool, dueDate: Date?, completionDate: Date?)],
        now: Date,
        calendar: Calendar = .current
    ) -> Progress {
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        var done = 0
        var open = 0
        for item in items {
            guard let due = item.dueDate else { continue }
            if item.isCompleted {
                if due < endOfToday, let completed = item.completionDate, calendar.isDate(completed, inSameDayAs: now) {
                    done += 1
                }
            } else if due < endOfToday {
                open += 1
            }
        }
        return Progress(done: done, total: done + open)
    }
}
