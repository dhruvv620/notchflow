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

/// Searches songs (Apple's public catalog) and hands one to Apple Music,
/// Spotify or YouTube Music.
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
        set { Defaults[.musicSearchTarget] = newValue.rawValue; objectWillChange.send() }
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
    private func scheduleSearch() {
        searchTask?.cancel()
        message = nil
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

    func play(_ result: MusicSearchResult) {
        switch target {
        case .appleMusic:
            Task {
                let answer = try? await AppleScriptHelper.execute(
                    MusicSearchPolicy.appleMusicLibraryScript(title: result.title, artist: result.artist))
                if answer?.stringValue == "played" {
                    message = "Playing \(result.title) in Apple Music."
                } else if let url = MusicSearchPolicy.appleMusicAppURL(result.storeURL) {
                    NSWorkspace.shared.open(url)
                    message = "Opened in Apple Music: it isn't in your library."
                }
            }
        case .spotify:
            if let url = MusicSearchPolicy.spotifySearchURL(title: result.title, artist: result.artist) {
                NSWorkspace.shared.open(url)
                message = "Opened in Spotify's search: press play there."
            }
        case .youtubeMusic:
            if let url = MusicSearchPolicy.youtubeMusicURL(title: result.title, artist: result.artist) {
                NSWorkspace.shared.open(url)
                message = "Opened on YouTube Music."
            }
        }
    }
}

/// The Music tab's search: a field, the player to use, and songs with artwork.
struct MusicSearchPanel: View {
    @ObservedObject private var search = MusicSearchService.shared
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
                Text(message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
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
                Image(systemName: search.target == .appleMusic ? "play.fill" : "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(search.target == .appleMusic ? "Play in Apple Music" : "Open in \(search.target.title)")
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
