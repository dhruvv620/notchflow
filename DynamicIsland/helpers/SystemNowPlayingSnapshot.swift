// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct NowPlayingUpdate: Decodable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Decodable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsedTime: Double?
    var shuffleMode: Int?
    var repeatMode: Int?
    var artworkData: String?
    var timestamp: String?
    var playbackRate: Double?
    var playing: Bool?
    var parentApplicationBundleIdentifier: String?
    var bundleIdentifier: String?
    private(set) var removedFields = Set<String>()

    init() {}
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, artist, album, duration, elapsedTime, shuffleMode, repeatMode, artworkData,
             timestamp, playbackRate, playing, parentApplicationBundleIdentifier, bundleIdentifier
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases where values.contains(key) {
            if try values.decodeNil(forKey: key) { removedFields.insert(key.rawValue) }
        }
        title = try values.decodeIfPresent(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        duration = try values.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try values.decodeIfPresent(Double.self, forKey: .elapsedTime)
        shuffleMode = try values.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try values.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try values.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try values.decodeIfPresent(String.self, forKey: .timestamp)
        playbackRate = try values.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try values.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try values.decodeIfPresent(String.self, forKey: .parentApplicationBundleIdentifier)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    }
}

enum SystemNowPlayingSnapshot {
    static func empty(at date: Date = Date()) -> PlaybackState {
        var state = PlaybackState(bundleIdentifier: "")
        state.title = ""; state.artist = ""; state.album = ""; state.lastUpdated = date
        return state
    }

    static func applying(_ update: NowPlayingUpdate, to previous: PlaybackState, now: Date = Date()) -> PlaybackState {
        let payload = update.payload
        let source = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier
        let sameSource = source == nil || source == previous.bundleIdentifier
        let isDiff = update.diff == true && sameSource
        var state = isDiff ? previous : empty(at: now)
        if let source { state.bundleIdentifier = source }
        let changesClock = payload.playing != nil || payload.playbackRate != nil
        if isDiff, changesClock, payload.elapsedTime == nil {
            let delta = previous.isPlaying ? max(0, now.timeIntervalSince(previous.lastUpdated)) * previous.playbackRate : 0
            state.currentTime = previous.currentTime + delta
        }
        if let value = payload.title { state.title = value }
        if let value = payload.artist { state.artist = value }
        if let value = payload.album { state.album = value }
        if let value = payload.duration, value.isFinite { state.duration = max(0, value) }
        if let value = payload.elapsedTime, value.isFinite { state.currentTime = max(0, value) }
        if let value = payload.playbackRate, value.isFinite { state.playbackRate = max(0, value) }
        if let value = payload.playing { state.isPlaying = value }
        if let value = payload.shuffleMode { state.isShuffled = value != 1 }
        if let value = payload.repeatMode { state.repeatMode = RepeatMode(rawValue: value) ?? .off }
        if let value = payload.artworkData { state.artwork = Data(base64Encoded: value, options: .ignoreUnknownCharacters) }
        for key in payload.removedFields {
            switch key {
            case "title": state.title = ""
            case "artist": state.artist = ""
            case "album": state.album = ""
            case "artworkData": state.artwork = nil
            case "duration": state.duration = 0
            case "elapsedTime": state.currentTime = 0
            case "playing": state.isPlaying = false
            case "playbackRate": state.playbackRate = 0
            case "bundleIdentifier", "parentApplicationBundleIdentifier":
                if source == nil { state.bundleIdentifier = "" }
            default: break
            }
        }
        if let timestamp = payload.timestamp, let date = date(from: timestamp) {
            state.lastUpdated = date
        } else if payload.elapsedTime != nil || changesClock || !isDiff {
            state.lastUpdated = now
        }
        return state
    }

    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
