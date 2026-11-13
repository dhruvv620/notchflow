/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// Reconciles asynchronous bookmark validation with the shelf's current state.
/// Keeping this decision pure makes the remove-vs-cleanup race testable without
/// AppKit or security-scoped bookmarks.
enum ShelfCleanupPolicy {
    static func removableIDs<ID: Hashable>(
        invalidCandidates: [ID: Data],
        currentBookmarks: [ID: Data]
    ) -> Set<ID> {
        Set(invalidCandidates.compactMap { candidate in
            currentBookmarks[candidate.key] == candidate.value ? candidate.key : nil
        })
    }
}
