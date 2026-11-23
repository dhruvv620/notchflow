// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Where a song found in the notch's search is played.
enum MusicSearchTarget: String, CaseIterable, Codable, Sendable {
    case appleMusic, spotify, youtubeMusic

    var title: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .youtubeMusic: return "YouTube Music"
        }
    }

    /// The player in use decides the default.
    static func preferred(forPlayer bundleID: String?) -> MusicSearchTarget {
        switch bundleID {
        case "com.apple.Music"?: return .appleMusic
        case "com.spotify.client"?: return .spotify
        case let id? where id.lowercased().contains("youtube"): return .youtubeMusic
        default: return .spotify
        }
    }
}

/// A song from the search.
struct MusicSearchResult: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    /// The song's page on Apple Music.
    let storeURL: URL?
    /// The exact Spotify track, when the result came from Spotify's search.
    var spotifyURI: String? = nil
    /// The track's album on Spotify, to play the song inside it.
    var spotifyAlbumURI: String? = nil
}

/// Searching songs (Apple's public catalog, no account needed) and handing
/// one to a player. Foundation only, so Build.command can check it alone.
enum MusicSearchPolicy {
    /// The iTunes Search API for songs.
    static func searchURL(_ query: String, country: String = "US", limit: Int = 8) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed), URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country.isEmpty ? "US" : country),
        ]
        return components?.url
    }

    static func results(from data: Data) -> [MusicSearchResult] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["results"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return items.compactMap { item in
            guard let id = item["trackId"] as? Int, let title = item["trackName"] as? String,
                  let artist = item["artistName"] as? String else { return nil }
            // The same song on several albums (single, album, deluxe) once.
            guard seen.insert((title + "|" + artist).lowercased()).inserted else { return nil }
            let artwork = (item["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "200x200")
            return MusicSearchResult(id: id, title: title, artist: artist, album: item["collectionName"] as? String ?? "",
                                     artworkURL: artwork.flatMap(URL.init(string:)),
                                     storeURL: (item["trackViewUrl"] as? String).flatMap(URL.init(string:)))
        }
    }

    /// Plays the song from the Music library if it's there; says "missing" otherwise.
    static func appleMusicLibraryScript(title: String, artist: String) -> String {
        let name = appleScriptString(title), by = appleScriptString(artist)
        return """
        tell application "Music"
            set found to (every track of library playlist 1 whose name is \(name) and artist contains \(by))
            if found is {} then set found to (search library playlist 1 for \(appleScriptString(title + " " + artist)) only songs)
            if found is not {} then
                play item 1 of found
                return "played"
            end if
        end tell
        return "missing"
        """
    }

    /// The song's page in the Music app (for songs not in the library).
    static func appleMusicAppURL(_ storeURL: URL?) -> URL? {
        guard let storeURL, var components = URLComponents(url: storeURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "music"
        return components.url
    }

    /// Spotify's search for the song, opened in the Spotify app.
    static func spotifySearchURL(title: String, artist: String) -> URL? {
        let query = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: ":/"))) ?? ""
        return URL(string: "spotify:search:" + query)
    }

    static func youtubeMusicURL(title: String, artist: String) -> URL? {
        var components = URLComponents(string: "https://music.youtube.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(title) \(artist)")]
        return components?.url
    }

    // MARK: Playing on Spotify and YouTube Music

    /// song.link (Odesli, free, no account): the same song on other services,
    /// from its Apple Music link.
    static func songLinkURL(for storeURL: URL?, country: String = "US") -> URL? {
        guard let storeURL else { return nil }
        var components = URLComponents(string: "https://api.song.link/v1-alpha.1/links")
        components?.queryItems = [URLQueryItem(name: "url", value: storeURL.absoluteString),
                                  URLQueryItem(name: "userCountry", value: country.isEmpty ? "US" : country)]
        return components?.url
    }

    /// One platform's link in song.link's answer ("spotify", "youtubeMusic").
    static func platformURL(_ platform: String, in data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let links = object["linksByPlatform"] as? [String: Any],
              let entry = links[platform] as? [String: Any],
              let url = entry["url"] as? String else { return nil }
        return URL(string: url)
    }

    /// "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=…" → "spotify:track:4uLU6hMCjMI75M1A2tKUQC".
    // MARK: YouTube Music without opening a tab

    /// A song's YouTube video id, from a YouTube or YouTube Music link.
    static func youtubeVideoID(from url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        var id: String?
        if host.hasSuffix("youtu.be") {
            id = url.pathComponents.dropFirst().first
        } else if host.hasSuffix("youtube.com") {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
        }
        guard let id, id.count == 11, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    static func youtubeMusicWatchURL(videoID: String) -> URL? {
        URL(string: "https://music.youtube.com/watch?v=\(videoID)")
    }

    /// AppleScript: the id of a browser window already playing YouTube Music (its front tab), or "".
    static func youtubeMusicPlayerWindowScript(bundleID: String, isChromium: Bool) -> String {
        let tab = isChromium ? "active tab" : "current tab"
        return """
        tell application id "\(bundleID)"
            repeat with w in windows
                try
                    if (URL of \(tab) of w) starts with "https://music.youtube.com" then return (id of w) as text
                end try
            end repeat
        end tell
        return ""
        """
    }

    /// AppleScript: plays another song in that window (its front tab goes to the song).
    static func youtubeMusicPlayScript(bundleID: String, isChromium: Bool, windowID: String, url: URL) -> String {
        let tab = isChromium ? "active tab" : "current tab"
        return "tell application id \"\(bundleID)\" to set URL of \(tab) of window id \(Int(windowID) ?? 0) to \(appleScriptString(url.absoluteString))"
    }

    /// AppleScript: closes the player window (after a long pause, to free its memory).
    static func youtubeMusicCloseScript(bundleID: String, windowID: String) -> String {
        "tell application id \"\(bundleID)\" to close window id \(Int(windowID) ?? 0)"
    }

    static func spotifyTrackURI(from url: URL?) -> String? {
        guard let url, url.host?.contains("spotify.com") == true else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "track"), parts.indices.contains(index + 1) else { return nil }
        let id = parts[index + 1]
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return "spotify:track:" + id
    }

    /// Plays a track in the Spotify app, in the background.
    static func spotifyPlayScript(trackURI: String, contextURI: String? = nil) -> String {
        let play = "tell application \"Spotify\" to play track \(appleScriptString(trackURI))"
        guard let contextURI else { return play }
        return play + " in context \(appleScriptString(contextURI))"
    }

    static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
