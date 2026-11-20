// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// The player songs found in the Music tab's search go to.
    static let musicSearchTarget = Key<String>("musicSearchTarget", default: "")
    /// A soft glow of the artwork's colors behind it.
    static let musicArtworkGlow = Key<Bool>("musicArtworkGlow", default: true)
}

/// Searches songs (Apple's public catalog) and plays one on Apple Music,
/// Spotify or YouTube Music without leaving the notch.
@MainActor
final class MusicSearchService: ObservableObject {
    static let shared = MusicSearchService()

    @Published var query = "" { didSet { scheduleSearch() } }
    @Published private(set) var results: [MusicSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var message: String?
    @Published var isOpen = false

    private var searchTask: Task<Void, Never>?

    var target: MusicSearchTarget {
        get { MusicSearchTarget(rawValue: Defaults[.musicSearchTarget]) ?? .preferred(forPlayer: MusicManager.shared.bundleIdentifier) }
        set { Defaults[.musicSearchTarget] = newValue.rawValue; objectWillChange.send(); scheduleSearch() }
    }

    private init() {}

    func close() {
        searchTask?.cancel()
        isOpen = false
        query = ""
        results = []
        message = nil
    }

    /// Searches a moment after typing stops.
    /// Whether this search goes to Spotify's own catalog (Spotify connected).
    var usesSpotifySearch: Bool { target == .spotify && SpotifyConnection.shared.isConnected }

    private func scheduleSearch() {
        searchTask?.cancel()
        message = nil
        if usesSpotifySearch, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
            let query = self.query
            isSearching = true
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                do {
                    let tracks = try await SpotifyConnection.shared.search(query)
                    guard !Task.isCancelled, let self else { return }
                    self.results = tracks.map { track in
                        MusicSearchResult(id: track.uri.hashValue, title: track.title, artist: track.artists, album: track.album,
                                          artworkURL: track.artworkURL, storeURL: nil, spotifyURI: track.uri)
                    }
                    self.isSearching = false
                    if self.results.isEmpty { self.message = "No songs found on Spotify." }
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.isSearching = false
                    self.message = error.localizedDescription
                }
            }
            return
        }
        guard let url = MusicSearchPolicy.searchURL(query, country: Locale.current.region?.identifier ?? "US") else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let self else { return }
                self.results = MusicSearchPolicy.results(from: data)
                self.isSearching = false
                if self.results.isEmpty { self.message = "No songs found." }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isSearching = false
                self.message = "Couldn't search right now."
            }
        }
    }

    @Published private(set) var startingID: Int?

    /// Plays the song without leaving the notch: from the Apple Music
    /// library, or in Spotify by its track (found through song.link), in the
    /// background. Only when that can't be done does a player open, and then
    /// behind what you're doing.
    func play(_ result: MusicSearchResult) {
        startingID = result.id
        message = nil
        let target = self.target
        Task { @MainActor in
            defer { startingID = nil }
            switch target {
            case .appleMusic:
                let answer = try? await AppleScriptHelper.execute(
                    MusicSearchPolicy.appleMusicLibraryScript(title: result.title, artist: result.artist))
                if answer?.stringValue == "played" {
                    message = "Playing \(result.title)."
                } else if let url = MusicSearchPolicy.appleMusicAppURL(result.storeURL) {
                    Self.openInBackground(url)
                    message = "Not in your library: opened in Music, behind this. Press play there."
                }
            case .spotify:
                // The exact track: from Spotify's search when connected, else through song.link.
                var uri = result.spotifyURI
                if uri == nil { uri = MusicSearchPolicy.spotifyTrackURI(from: await Self.link(for: result, on: "spotify")) }
                if let uri {
                    do {
                        try await Self.playInBackground(uri)
                        message = "Playing \(result.title) on Spotify."
                    } catch {
                        // Found, but macOS didn't let NotchFlow tell Spotify to play.
                        message = "Allow NotchFlow to control Spotify: System Settings › Privacy & Security › Automation."
                    }
                } else if let url = MusicSearchPolicy.spotifySearchURL(title: result.title, artist: result.artist) {
                    Self.openInBackground(url)
                    message = SpotifyConnection.shared.isConnected
                        ? "Couldn't find the exact track: opened Spotify's search, behind this."
                        : "Couldn't find the exact track: opened Spotify's search. Connect Spotify in Settings › Music for exact results."
                }
            case .youtubeMusic:
                // A website plays in a browser tab: the exact song, opened behind what you're doing.
                if let url = await Self.link(for: result, on: "youtubeMusic") {
                    Self.openInBackground(url)
                    message = "Playing \(result.title) on YouTube Music, in a browser tab behind this."
                } else if let url = MusicSearchPolicy.youtubeMusicURL(title: result.title, artist: result.artist) {
                    Self.openInBackground(url)
                    message = "Opened YouTube Music's search, behind this."
                }
            }
        }
    }

    /// Plays a track in Spotify without Spotify coming forward: a Spotify
    /// that isn't running is started hidden first (an app launched by a
    /// command otherwise opens its window in front), and if it still jumps
    /// forward when it starts playing, it's hidden again and you're back
    /// where you were.
    private static func playInBackground(_ uri: String) async throws {
        let spotifyID = "com.spotify.client"
        let previous = NSWorkspace.shared.frontmostApplication
        var launchedNow = false
        if NSRunningApplication.runningApplications(withBundleIdentifier: spotifyID).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            launchedNow = true
            // Ready to take commands a moment after it starts.
            try? await Task.sleep(for: .seconds(2.5))
        }
        try await AppleScriptHelper.executeVoid(MusicSearchPolicy.spotifyPlayScript(trackURI: uri))
        try? await Task.sleep(for: .milliseconds(400))
        guard let spotify = NSRunningApplication.runningApplications(withBundleIdentifier: spotifyID).first else { return }
        let spotifyWasInFront = previous?.bundleIdentifier == spotifyID
        if spotify.isActive, !spotifyWasInFront {
            spotify.hide()
            if let previous, previous.bundleIdentifier != Bundle.main.bundleIdentifier { previous.activate() }
        } else if launchedNow, !spotify.isHidden {
            spotify.hide()
        }
    }

    /// The song's link on another service, from song.link.
    private static func link(for result: MusicSearchResult, on platform: String) async -> URL? {
        guard let url = MusicSearchPolicy.songLinkURL(for: result.storeURL, country: Locale.current.region?.identifier ?? "US"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return MusicSearchPolicy.platformURL(platform, in: data)
    }

    /// Opens a link without bringing its app to the front.
    private static func openInBackground(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}

/// The Music tab's search: a field, the player to use, and songs with artwork.
struct MusicSearchPanel: View {
    @ObservedObject private var search = MusicSearchService.shared
    @ObservedObject private var spotify = SpotifyConnection.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @FocusState private var focused: Bool
    @State private var token = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Search songs", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onExitCommand { search.close() }
                if search.isSearching { ProgressView().controlSize(.mini) }
                Picker("", selection: Binding(get: { search.target }, set: { search.target = $0 })) {
                    ForEach(MusicSearchTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .help("Where a song you pick plays")
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))

            if let message = search.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            } else if search.target == .spotify && !spotify.isConnected {
                Button("Connect Spotify for exact results (Settings › Music)") { SettingsWindowController.shared.showWindow() }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(appearance.accentColor)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(search.results) { result in row(result) }
                }
            }
            .onHover { vm.setScrollGestureSuppression($0, token: token) }
        }
        .onAppear {
            focused = true
            vm.setAutoCloseSuppression(true, token: token)
        }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: token)
            vm.setScrollGestureSuppression(false, token: token)
        }
    }

    private func row(_ result: MusicSearchResult) -> some View {
        Button { search.play(result) } label: {
            HStack(spacing: 8) {
                AsyncImage(url: result.artworkURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
                        .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.secondary))
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(result.album.isEmpty ? result.artist : "\(result.artist) · \(result.album)")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if search.startingID == result.id {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .contentShape(Rectangle())
            // A pointing hand, not the text cursor from the search field above.
            .background(PointingHandCursorArea())
        }
        .buttonStyle(.plain)
        .help("Play on \(search.target.title)")
    }
}

/// A soft glow of the artwork's own colors behind it, brighter while playing.
struct ArtworkGlow: ViewModifier {
    @ObservedObject private var music = MusicManager.shared
    @Default(.musicArtworkGlow) private var enabled
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                Image(nsImage: music.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .scaleEffect(1.12)
                    .blur(radius: 14)
                    .opacity(music.isPlaying ? 0.75 : 0.3)
                    .animation(.smooth(duration: 0.6), value: music.isPlaying)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func artworkGlow(cornerRadius: CGFloat) -> some View { modifier(ArtworkGlow(cornerRadius: cornerRadius)) }
}
