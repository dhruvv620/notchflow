// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// "Song radio" for a song picked in the notch: songs like it to play after
/// it, so Next goes on the way Spotify's own radio and Autoplay do. Spotify
/// doesn't give new apps its recommendations, so the songs come from
/// Deezer's public artist radio (the artist and similar artists, no account)
/// and are then found on Spotify. Foundation only, so Build.command can check
/// it alone.
enum SongRadioPolicy {
    struct Song: Equatable, Sendable {
        let title: String
        let artist: String
    }

    /// How many songs follow the one you picked.
    static let length = 20

    /// Finds the song on Deezer, for its artist.
    static func deezerSearchURL(title: String, artist: String) -> URL? {
        let query = artist.isEmpty
            ? "track:\"\(clean(title))\""
            : "artist:\"\(clean(artist))\" track:\"\(clean(title))\""
        var components = URLComponents(string: "https://api.deezer.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "1")]
        return components?.url
    }

    static func deezerArtistID(from data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (object["data"] as? [[String: Any]])?.first,
              let artist = first["artist"] as? [String: Any] else { return nil }
        return (artist["id"] as? NSNumber)?.intValue
    }

    /// The artist's radio: their songs and similar artists', mixed.
    static func deezerRadioURL(artistID: Int) -> URL? {
        URL(string: "https://api.deezer.com/artist/\(artistID)/radio?limit=40")
    }

    static func songs(fromRadio data: Data) -> [Song] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let title = (item["title_short"] as? String) ?? (item["title"] as? String),
                  let artist = (item["artist"] as? [String: Any])?["name"] as? String,
                  !title.isEmpty, !artist.isEmpty else { return nil }
            return Song(title: title, artist: artist)
        }
    }

    /// The songs to play after `seed`: without the seed itself or repeats,
    /// at most three by one artist (a radio, not the artist's top songs),
    /// in the radio's order.
    static func upNext(_ songs: [Song], after seed: Song, length: Int = length) -> [Song] {
        var seen: Set<String> = [key(seed)]
        var perArtist: [String: Int] = [:]
        var result: [Song] = []
        for song in songs where result.count < length {
            guard seen.insert(key(song)).inserted else { continue }
            let artist = normalized(song.artist)
            guard perArtist[artist, default: 0] < 3 else { continue }
            perArtist[artist, default: 0] += 1
            result.append(song)
        }
        return result
    }

    /// Spotify search for one song.
    static func spotifyQuery(for song: Song) -> String {
        "track:\"\(clean(song.title))\" artist:\"\(clean(song.artist))\""
    }

    /// Whether Spotify's result is that song (by that artist), not a cover
    /// or a namesake.
    static func isMatch(title: String, artists: String, for song: Song) -> Bool {
        let wanted = normalized(song.artist)
        let found = normalized(artists)
        guard !wanted.isEmpty, found.contains(wanted) || wanted.contains(found) else { return false }
        let wantedTitle = normalized(song.title), foundTitle = normalized(title)
        return foundTitle.contains(wantedTitle) || wantedTitle.contains(foundTitle)
    }

    /// Lowercased, without accents and without "(feat. …)" or " - Remastered" parts.
    static func normalized(_ value: String) -> String {
        var text = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for opener in ["(", "[", " - "] {
            if let range = text.range(of: opener) { text = String(text[..<range.lowerBound]) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(_ song: Song) -> String { normalized(song.title) + "|" + normalized(song.artist) }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
    }
}
