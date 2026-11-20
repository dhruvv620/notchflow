// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct MusicSearchRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "MusicSearchRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = MusicSearchPolicy
        try require(P.searchURL("a") == nil && P.searchURL("   ") == nil, "Searched for nothing")
        let url = P.searchURL("Noah Kahan stick season", country: "IN")?.absoluteString ?? ""
        try require(url.hasPrefix("https://itunes.apple.com/search?") && url.contains("term=Noah%20Kahan%20stick%20season")
                    && url.contains("entity=song") && url.contains("country=IN"), "Search URL: \(url)")
        let json = #"""
        {"resultCount":3,"results":[
          {"trackId":1,"trackName":"You're Gonna Go Far","artistName":"Noah Kahan","collectionName":"Stick Season",
           "artworkUrl100":"https://is1.mzstatic.com/a/100x100bb.jpg","trackViewUrl":"https://music.apple.com/us/album/x/123?i=1"},
          {"trackId":2,"trackName":"You're Gonna Go Far","artistName":"Noah Kahan","collectionName":"Stick Season (Deluxe)"},
          {"trackId":3,"trackName":"Stick Season","artistName":"Noah Kahan"},
          {"wrapperType":"artist"}
        ]}
        """#
        let results = P.results(from: Data(json.utf8))
        try require(results.map(\.id) == [1, 3], "Results: \(results.map(\.id))")
        try require(results[0].artworkURL?.absoluteString == "https://is1.mzstatic.com/a/200x200bb.jpg", "Bigger artwork")
        try require(P.appleMusicAppURL(results[0].storeURL)?.absoluteString == "music://music.apple.com/us/album/x/123?i=1", "Music app URL")
        let script = P.appleMusicLibraryScript(title: "Say \"Hi\"", artist: "AC\\DC")
        try require(script.contains(#"whose name is "Say \"Hi\"" and artist contains "AC\\DC""#) && script.contains("play item 1 of found"),
                    "Library script: \(script)")
        try require(P.spotifySearchURL(title: "You're Gonna Go Far", artist: "Noah Kahan")?.absoluteString
                    == "spotify:search:You're%20Gonna%20Go%20Far%20Noah%20Kahan", "Spotify URL: \(P.spotifySearchURL(title: "You're Gonna Go Far", artist: "Noah Kahan")?.absoluteString ?? "")")
        try require(P.youtubeMusicURL(title: "Kesariya", artist: "Arijit Singh")?.absoluteString
                    == "https://music.youtube.com/search?q=Kesariya%20Arijit%20Singh", "YouTube Music URL")
        try require(MusicSearchTarget.preferred(forPlayer: "com.apple.Music") == .appleMusic
                    && MusicSearchTarget.preferred(forPlayer: "com.spotify.client") == .spotify
                    && MusicSearchTarget.preferred(forPlayer: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod.youtube") == .youtubeMusic,
                    "Preferred target")
        print("Music search: OK")
    }
}
