// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// A locally stored teleprompter script. Array order is meaningful and stays
/// stable across saves so future organizers can reorder without a migration.
struct CuelyScript: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var text: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = max(updatedAt ?? createdAt, createdAt)
    }
}

enum CuelyScriptValidationError: LocalizedError, Equatable, Sendable {
    case emptyTitle
    case emptyText
    case titleTooLong(maximum: Int)
    case textTooLong(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Enter a script title."
        case .emptyText:
            return "Enter some script text."
        case .titleTooLong(let maximum):
            return "Script titles can contain at most \(maximum) characters."
        case .textTooLong(let maximum):
            return "Scripts can contain at most \(maximum) characters."
        }
    }
}

enum CuelyScriptPolicy {
    static let maximumTitleLength = 120
    static let maximumTextLength = 100_000

    static func validated(title: String, text: String) throws -> (title: String, text: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CuelyScriptValidationError.emptyTitle }
        guard title.count <= maximumTitleLength else {
            throw CuelyScriptValidationError.titleTooLong(maximum: maximumTitleLength)
        }

        // Normalize pasted Windows/legacy line endings without changing the
        // author's paragraph indentation or internal whitespace.
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CuelyScriptValidationError.emptyText
        }
        guard text.count <= maximumTextLength else {
            throw CuelyScriptValidationError.textTooLong(maximum: maximumTextLength)
        }
        return (title, text)
    }

    static func duplicateTitle(_ title: String) -> String {
        let suffix = " Copy"
        return String(title.prefix(maximumTitleLength - suffix.count)) + suffix
    }
}
