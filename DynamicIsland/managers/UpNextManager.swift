// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Combine
import Foundation
import SwiftUI

/// What plays next, from Spotify's queue or the playing Apple Music playlist.
@MainActor
final class UpNextManager: ObservableObject {
    static let shared = UpNextManager()

    @Published private(set) var tracks: [UpNextTrack] = []
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    private init() {
        let music = MusicManager.shared
        music.$songTitle.removeDuplicates().map { _ in true }
            .merge(with: music.$bundleIdentifier.removeDuplicates().map { _ in true })
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    var next: UpNextTrack? { tracks.first }

    func refresh() {
        refreshTask?.cancel()
        let music = MusicManager.shared
        let bundle = music.bundleIdentifier ?? ""
        let current = music.songTitle
        refreshTask = Task { [weak self] in
            var result: [UpNextTrack] = []
            if bundle == "com.spotify.client" {
                result = await Self.spotifyQueue()
            } else if bundle == "com.apple.Music" {
                if let output = try? await AppleScriptHelper.execute(UpNextPolicy.appleMusicScript)?.stringValue {
                    result = UpNextPolicy.appleMusicTracks(from: output)
                }
            }
            guard !Task.isCancelled else { return }
            self?.tracks = UpNextPolicy.excludingCurrent(result, currentTitle: current)
        }
    }

    /// Skips forward to the chosen upcoming track.
    func skip(to track: UpNextTrack) {
        guard let index = tracks.firstIndex(of: track) else { return }
        Task {
            for step in 0...index {
                MusicManager.shared.nextTrack()
                if step < index { try? await Task.sleep(for: .milliseconds(350)) }
            }
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    private static func spotifyQueue() async -> [UpNextTrack] {
        guard let token = await SpotifyAuthManager.shared.validAccessToken() else { return [] }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return UpNextPolicy.spotifyQueue(from: data)
    }
}

/// "Up next" under the artist; opens a menu of upcoming tracks to skip to.
struct UpNextRow: View {
    @ObservedObject private var upNext = UpNextManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        if let next = upNext.next {
            Menu {
                Section("Up Next") {
                    ForEach(upNext.tracks) { track in
                        Button(track.artist.isEmpty ? track.title : "\(track.title) – \(track.artist)") {
                            upNext.skip(to: track)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Up next")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(appearance.accentColor.opacity(0.9))
                    Text(next.artist.isEmpty ? next.title : "\(next.title) – \(next.artist)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
            .help("Skip ahead to a track in the queue")
            .transition(.opacity)
        }
    }
}
