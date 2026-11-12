// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

private actor ReceivedUpdates {
    var updates: [NowPlayingUpdate] = []
    func append(_ value: NowPlayingUpdate) { updates.append(value) }
}

@main
struct SystemMediaRegression {
    static func main() async throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "SystemMediaRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func decode(_ json: String) throws -> NowPlayingUpdate { try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8)) }
        let origin = Date(timeIntervalSince1970: 1_767_225_600)
        let full = try decode(#"{"diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"Track","artist":"Artist","duration":240,"elapsedTime":10,"playing":true,"artworkData":"YWJj","timestamp":"2026-01-01T00:00:00.125Z"}}"#)
        let initial = SystemNowPlayingSnapshot.applying(full, to: SystemNowPlayingSnapshot.empty(), now: origin)
        try require(initial.artwork == Data("abc".utf8) && initial.title == "Track", "Full media snapshot lost metadata/artwork")
        try require(abs(initial.lastUpdated.timeIntervalSince(origin) - 0.125) < 0.001, "Fractional media timestamp was ignored")
        let progress = try decode(#"{"diff":true,"payload":{"elapsedTime":12}}"#)
        let updated = SystemNowPlayingSnapshot.applying(progress, to: initial, now: origin.addingTimeInterval(2))
        try require(updated.title == "Track" && updated.artwork == initial.artwork && updated.isPlaying && updated.currentTime == 12, "Progress-only update discarded artwork or playback state")
        let pause = try decode(#"{"diff":true,"payload":{"playing":false}}"#)
        let paused = SystemNowPlayingSnapshot.applying(pause, to: updated, now: origin.addingTimeInterval(5))
        try require(paused.currentTime == 15 && !paused.isPlaying, "Pause did not freeze the interpolated position")
        let play = try decode(#"{"diff":true,"payload":{"playing":true}}"#)
        let resumed = SystemNowPlayingSnapshot.applying(play, to: paused, now: origin.addingTimeInterval(60))
        try require(resumed.currentTime == 15 && resumed.lastUpdated == origin.addingTimeInterval(60), "Resume reused a stale clock and jumped forward")
        let removed = try decode(#"{"diff":true,"payload":{"artist":null,"artworkData":null}}"#)
        let cleared = SystemNowPlayingSnapshot.applying(removed, to: initial, now: origin)
        try require(cleared.artist.isEmpty && cleared.artwork == nil && cleared.title == "Track", "Null diff fields did not clear previous metadata")
        let movie = try decode(#"{"diff":true,"payload":{"bundleIdentifier":"com.apple.Safari","title":"A movie","playing":true}}"#)
        let video = SystemNowPlayingSnapshot.applying(movie, to: initial, now: origin)
        try require(video.bundleIdentifier == "com.apple.Safari" && video.title == "A movie" && video.artist.isEmpty && video.artwork == nil && video.isPlaying, "Switching from Spotify leaked its artwork or required a video artist")
        let empty = SystemNowPlayingSnapshot.applying(try decode(#"{"diff":false,"payload":{}}"#), to: initial, now: origin)
        try require(empty.title.isEmpty && empty.bundleIdentifier.isEmpty && !empty.isPlaying, "Ended media left stale playback visible")

        // A pipe can split a multi-byte title anywhere; decode complete byte lines,
        // rather than losing a whole update when a chunk is not valid UTF-8 alone.
        let handler = JSONLinesPipeHandler()
        let pipe = await handler.getPipe()
        let received = ReceivedUpdates()
        let reading = Task { await handler.readJSONLines(as: NowPlayingUpdate.self) { await received.append($0) } }
        let text = "{\"payload\":{\"title\":\"Music 🎵\",\"playing\":true},\"diff\":false}\n"
        let bytes = Array(text.utf8)
        let split = bytes.firstIndex(of: 0xF0)! + 2
        try pipe.fileHandleForWriting.write(contentsOf: Data(bytes[..<split]))
        try pipe.fileHandleForWriting.write(contentsOf: Data(bytes[split...]))
        try pipe.fileHandleForWriting.close()
        await reading.value
        let updates = await received.updates
        try require(updates.count == 1 && updates[0].payload.title == "Music 🎵", "Split UTF-8 pipe reads lost a live update")
        await handler.close()
        print("System media snapshots, clocks, source changes and stream checks passed")
    }
}
