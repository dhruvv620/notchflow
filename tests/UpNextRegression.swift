// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct UpNextRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "UpNextRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let json = #"""
        {"currently_playing":{"name":"Now"},"queue":[
          {"name":"Song A","artists":[{"name":"Artist 1"},{"name":"Artist 2"}]},
          {"name":"Episode B","show":{"name":"A Podcast"}},
          {"name":""},
          {"name":"C","artists":[]},{"name":"D"},{"name":"E"},{"name":"F"}]}
        """#
        let spotify = UpNextPolicy.spotifyQueue(from: Data(json.utf8))
        try require(spotify.first == UpNextTrack(title: "Song A", artist: "Artist 1, Artist 2"), "Artists not joined")
        try require(spotify[1] == UpNextTrack(title: "Episode B", artist: "A Podcast"), "Podcast show not used")
        try require(spotify.count == 4 && !spotify.contains { $0.title.isEmpty }, "Queue not limited or blank kept: \(spotify.count)")
        try require(UpNextPolicy.spotifyQueue(from: Data("{}".utf8)).isEmpty, "Missing queue gave tracks")

        let music = UpNextPolicy.appleMusicTracks(from: "Track One\tBand\n\nTrack Two\t\nNo Tab Here\n")
        try require(music == [UpNextTrack(title: "Track One", artist: "Band"), UpNextTrack(title: "Track Two", artist: ""),
                              UpNextTrack(title: "No Tab Here", artist: "")], "Apple Music output misread: \(music)")
        try require(UpNextPolicy.excludingCurrent(music, currentTitle: "track one").first?.title == "Track Two", "Current song kept at the head")
        try require(UpNextPolicy.excludingCurrent(music, currentTitle: "Other").count == 3, "A different song was dropped")
        print("Up next checks passed")
    }
}
