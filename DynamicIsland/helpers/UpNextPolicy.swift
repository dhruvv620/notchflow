// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Parses upcoming-track answers from Spotify and Apple Music.
/// Pure logic (Foundation only), so Build.command can check it alone.
struct UpNextTrack: Equatable, Sendable, Identifiable {
    let title: String
    let artist: String
    var id: String { "\(title)\u{1F}\(artist)" }
}

enum UpNextPolicy {
    static let limit = 5

    /// Spotify Web API `GET /v1/me/player/queue`: `{ "queue": [ { "name", "artists": [{ "name" }] } ] }`.
    static func spotifyQueue(from data: Data) -> [UpNextTrack] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queue = object["queue"] as? [[String: Any]] else { return [] }
        return queue.prefix(limit).compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let show = (item["show"] as? [String: Any])?["name"] as? String
            return UpNextTrack(title: name, artist: artists.isEmpty ? (show ?? "") : artists.joined(separator: ", "))
        }
    }

    /// Apple Music script output: one "title<TAB>artist" per line.
    static func appleMusicTracks(from output: String) -> [UpNextTrack] {
        output.split(whereSeparator: \.isNewline).prefix(limit).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let title = parts.first?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
            return UpNextTrack(title: title, artist: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
        }
    }

    /// Drops the playing song if a source repeats it at the head of its queue.
    static func excludingCurrent(_ tracks: [UpNextTrack], currentTitle: String) -> [UpNextTrack] {
        guard let first = tracks.first, first.title.caseInsensitiveCompare(currentTitle) == .orderedSame else { return tracks }
        return Array(tracks.dropFirst())
    }

    /// The upcoming tracks in the playing Apple Music playlist (not when shuffled).
    static let appleMusicScript = """
    tell application "Music"
        if player state is stopped then return ""
        if shuffle enabled then return ""
        set pl to current playlist
        set idx to index of current track
        set total to count of tracks of pl
        set out to ""
        repeat with i from (idx + 1) to (idx + 5)
            if i > total then exit repeat
            set t to track i of pl
            set out to out & (name of t) & tab & (artist of t) & linefeed
        end repeat
        return out
    end tell
    """
}
