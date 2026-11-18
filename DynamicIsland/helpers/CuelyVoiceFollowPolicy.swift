// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// One word of a script, with where it sits in the script text (UTF-16, so it
/// can be highlighted in an NSTextView directly).
struct CuelyWord: Equatable, Sendable {
    let normalized: String
    let range: NSRange
}

/// Follows the reader through a script: matches the last few words the speech
/// recognizer heard against the script near the current position.
/// Pure Foundation, so Build.command can check it alone.
enum CuelyVoiceFollowPolicy {
    /// How many recent spoken words are matched.
    static let tailLength = 8
    /// How far behind and ahead of the current position to look.
    static let lookBehind = 12
    static let lookAhead = 45

    static func words(in text: String) -> [CuelyWord] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{N}'’]*"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let word = normalize(ns.substring(with: match.range))
            return word.isEmpty ? nil : CuelyWord(normalized: word, range: match.range)
        }
    }

    static func spokenWords(in transcript: String) -> [String] {
        // Only the end of the transcript matters; keep the work small.
        let tail = String(transcript.suffix(400))
        return words(in: tail).map(\.normalized).suffix(tailLength).map { $0 }
    }

    static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }

    /// Whether a heard word is the script word, allowing for small recognition slips.
    static func matches(_ spoken: String, _ written: String) -> Bool {
        if spoken == written { return true }
        let shorter = min(spoken.count, written.count)
        if shorter >= 4, spoken.hasPrefix(written) || written.hasPrefix(spoken) { return true }
        if shorter >= 5, abs(spoken.count - written.count) <= 1, editDistance(spoken, written) <= 1 { return true }
        return false
    }

    /// The new position (index of the next word to read) after hearing
    /// `spoken`, or nil when the words do not match the script near `cursor`.
    static func advance(script: [CuelyWord], spoken: [String], cursor: Int) -> Int? {
        let tail = Array(spoken.suffix(tailLength))
        guard let last = tail.last, !script.isEmpty else { return nil }
        let cursor = min(max(0, cursor), script.count)
        let lower = max(0, cursor - lookBehind)
        let upper = min(script.count, cursor + lookAhead)
        guard lower < upper else { return nil }

        var best: (end: Int, score: Int)?
        for end in lower..<upper where matches(last, script[end].normalized) {
            let start = max(0, end - tail.count - 3)
            let written = script[start...end].map(\.normalized)
            let score = commonSubsequence(tail, written)
            let needed: Int
            if tail.count == 1 {
                // A single word only counts right where the reader is, and if it is not a filler word.
                needed = (last.count >= 4 && end >= cursor && end <= cursor + 2) ? 1 : Int.max
            } else {
                needed = min(3, tail.count)
            }
            // Jumping back means re-reading: ask for more evidence.
            let required = end + 1 < cursor ? max(needed, 4) : needed
            guard score >= required else { continue }
            if let current = best {
                let closer = abs(end + 1 - cursor) < abs(current.end + 1 - cursor)
                if score > current.score || (score == current.score && closer) { best = (end, score) }
            } else {
                best = (end, score)
            }
        }
        return best.map { $0.end + 1 }
    }

    /// Script word index at a character position (for click-to-jump).
    static func wordIndex(atCharacter location: Int, in script: [CuelyWord]) -> Int? {
        guard !script.isEmpty else { return nil }
        if let index = script.firstIndex(where: { NSMaxRange($0.range) > location }) { return index }
        return script.count - 1
    }

    private static func commonSubsequence(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = matches(x, y) ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(1, b.count) where !b.isEmpty {
                let temp = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = temp
            }
        }
        return row[b.count]
    }
}

/// How big the Cuely panel is, chosen from the tab.
enum CuelyPanelSize: Int, CaseIterable, Sendable {
    case regular = 0
    case large = 1
    case extraLarge = 2

    var title: String {
        switch self {
        case .regular: return "Regular"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }

    var extraHeight: Double {
        switch self {
        case .regular: return 0
        case .large: return 140
        case .extraLarge: return 280
        }
    }

    var minimumWidth: Double {
        switch self {
        case .regular: return 0
        case .large: return 780
        case .extraLarge: return 960
        }
    }

    var next: CuelyPanelSize { CuelyPanelSize(rawValue: (rawValue + 1) % Self.allCases.count) ?? .regular }
}
