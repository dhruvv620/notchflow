// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Which synced lyric line is being sung, and how far through it the singer is.
/// Pure logic (Foundation only), so Build.command can check it alone.
enum LyricsKaraokePolicy {
    struct Position: Equatable, Sendable {
        /// Index of the current line, or nil before the first line.
        let index: Int?
        /// 0...1 through the current line, for the sweep highlight.
        let progress: Double
        /// The line has no words: an instrumental stretch.
        let isInstrumental: Bool
    }

    /// The last line has no successor; assume it lasts this long.
    static let lastLineDuration: TimeInterval = 5
    /// A line's sweep never takes longer than this, so a long instrumental
    /// gap after it does not stretch the highlight over half a minute.
    static let maximumSweep: TimeInterval = 8

    /// - Parameter timestamps: line start times in seconds, ascending.
    static func position(timestamps: [TimeInterval], texts: [String], at time: TimeInterval) -> Position {
        guard !timestamps.isEmpty, timestamps.count == texts.count, time.isFinite else {
            return Position(index: nil, progress: 0, isInstrumental: false)
        }
        // Last line whose start has passed.
        var low = 0, high = timestamps.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if timestamps[mid] <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return Position(index: nil, progress: 0, isInstrumental: false) }

        let start = timestamps[found]
        let next = found + 1 < timestamps.count ? timestamps[found + 1] : start + lastLineDuration
        let duration = max(0.3, min(next - start, maximumSweep))
        let progress = min(1, max(0, (time - start) / duration))
        let text = texts[found].trimmingCharacters(in: .whitespacesAndNewlines)
        return Position(index: found, progress: progress, isInstrumental: text.isEmpty || text == "♪")
    }
}
