// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct SongRadioRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "SongRadioRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = SongRadioPolicy
        typealias Song = SongRadioPolicy.Song

        let search = P.deezerSearchURL(title: "I Wanna Love You", artist: "Akon")?.absoluteString ?? ""
        try require(search == "https://api.deezer.com/search?q=artist:%22Akon%22%20track:%22I%20Wanna%20Love%20You%22&limit=1",
                    "Deezer search: \(search)")
        try require(P.deezerArtistID(from: Data(#"{"data":[{"id":3135556,"title":"I Wanna Love You","artist":{"id":1171,"name":"Akon"}}],"total":1}"#.utf8)) == 1171,
                    "Artist id")
        try require(P.deezerArtistID(from: Data(#"{"data":[],"total":0}"#.utf8)) == nil, "No result")
        try require(P.deezerRadioURL(artistID: 1171)?.absoluteString == "https://api.deezer.com/artist/1171/radio?limit=40", "Radio URL")

        let radio = P.songs(fromRadio: Data(#"""
        {"data":[
          {"id":1,"title":"Smack That (feat. Eminem)","title_short":"Smack That","artist":{"id":1171,"name":"Akon"}},
          {"id":2,"title":"Yeah!","artist":{"id":7,"name":"Usher"}},
          {"id":3,"title_short":"","artist":{"id":7,"name":"Usher"}},
          {"id":4,"title":"I Wanna Love You","artist":{"id":1171,"name":"Akon"}}
        ]}
        """#.utf8))
        try require(radio == [Song(title: "Smack That", artist: "Akon"), Song(title: "Yeah!", artist: "Usher"),
                              Song(title: "I Wanna Love You", artist: "Akon")], "Radio songs: \(radio)")

        let seed = Song(title: "I Wanna Love You", artist: "Akon")
        let many = [Song(title: "I wanna love you (Radio Edit)", artist: "AKON"), Song(title: "A", artist: "Usher"),
                    Song(title: "B", artist: "Usher"), Song(title: "C", artist: "Usher"), Song(title: "D", artist: "Usher"),
                    Song(title: "a", artist: "Usher"), Song(title: "Bailando", artist: "Enrique Iglesias")]
        let next = P.upNext(many, after: seed)
        try require(next.map(\.title) == ["A", "B", "C", "Bailando"], "Up next: \(next.map(\.title))")
        try require(P.upNext(many, after: seed, length: 2).count == 2, "Length cap")

        try require(P.spotifyQuery(for: Song(title: "Say \"Hi\"", artist: "Akon")) == #"track:"Say Hi" artist:"Akon""#, "Spotify query")
        try require(P.isMatch(title: "Smack That", artists: "Akon, Eminem", for: Song(title: "Smack That", artist: "Akon")), "Match")
        try require(P.isMatch(title: "Crazy In Love (feat. Jay-Z)", artists: "Beyoncé, JAY-Z", for: Song(title: "Crazy in Love", artist: "Beyonce")),
                    "Match without accents or the feature")
        try require(!P.isMatch(title: "Smack That", artists: "Karaoke Stars", for: Song(title: "Smack That", artist: "Akon")), "A cover")
        try require(!P.isMatch(title: "Lonely", artists: "Akon", for: Song(title: "Smack That", artist: "Akon")), "Another song")
        print("Song radio: OK")
    }
}
