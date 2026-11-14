// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Automatic follows macOS Now Playing. A selected app stays pinned until the
/// user chooses Automatic again; opening a source never starts playback.
struct MediaSourcePicker: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var music = MusicManager.shared
    @State private var showingSources = false
    @State private var appName: String?
    @State private var token = UUID()

    var body: some View {
        Button { showingSources.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: music.selectedMediaSource == .nowPlaying ? "waveform" : "pin.fill")
                Text(appName ?? sourceTitle(music.selectedMediaSource)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary).frame(maxWidth: 150, alignment: .trailing)
        }
        .buttonStyle(.plain).help("Choose media source")
        .accessibilityLabel("Media source: \(appName ?? sourceTitle(music.selectedMediaSource))")
        .onChange(of: music.bundleIdentifier, initial: true) { _, identifier in appName = displayName(identifier) }
        .popover(isPresented: $showingSources, arrowEdge: .bottom) { sourcePopover }
        .onChange(of: showingSources) { _, shown in
            vm.isMediaSourcePopoverActive = shown
            vm.setAutoCloseSuppression(shown, token: token)
            if !shown { vm.shouldRecheckHover.toggle() }
        }
        .onDisappear {
            vm.isMediaSourcePopoverActive = false
            vm.setAutoCloseSuppression(false, token: token)
        }
    }

    private var sources: [MediaControllerType] {
        MediaControllerType.allCases.filter { source in
            source == .nowPlaying || source == .spotify || source == .appleMusic
                || bundleID(source).flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
        }
    }
    private var sourcePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Media source").font(.headline)
            Text("Automatic follows audio and video playing on your Mac. Choose an app to keep its controls here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(sources) { source in
                Button {
                    music.selectMediaSource(source)
                    showingSources = false
                } label: {
                    HStack(spacing: 9) {
                        if let identifier = bundleID(source) {
                            AppIcon(for: identifier).resizable().scaledToFit().frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "waveform.circle.fill").font(.system(size: 20)).frame(width: 20)
                        }
                        Text(sourceTitle(source))
                        Spacer()
                        if music.selectedMediaSource == source { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider()
            if let error = music.mediaSourceError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") { music.forceUpdate() }
                Spacer()
                if music.bundleIdentifier != nil {
                    Button("Open app", systemImage: "arrow.up.right") { music.openMusicApp() }
                }
            }.controlSize(.small)
        }.font(.system(size: 12)).padding(14).frame(width: 260)
    }

    private func sourceTitle(_ source: MediaControllerType) -> String {
        source == .nowPlaying ? "Automatic" : source.localizedName
    }
    private func bundleID(_ source: MediaControllerType) -> String? {
        switch source {
        case .nowPlaying: return nil
        case .spotify: return SpotifyController.bundleIdentifier
        case .appleMusic: return "com.apple.Music"
        case .youtubeMusic: return YouTubeMusicConfiguration.default.bundleIdentifier
        case .amazonMusic: return AmazonMusicController.bundleIdentifier
        case .cider: return CiderController.bundleIdentifier
        }
    }
    private func displayName(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { return app.localizedName }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }
}
