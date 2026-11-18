// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Lyrics shown under the player in the Music tab (toggled by its lyrics button).
    static let musicLyricsExpanded = Key<Bool>("musicLyricsExpanded", default: false)
}

/// The lyrics button in the Music tab header.
struct MusicLyricsToggle: View {
    @Default(.musicLyricsExpanded) private var expanded
    @Default(.enableLyrics) private var lyricsEnabled
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    private var isOn: Bool { expanded && lyricsEnabled }

    var body: some View {
        Button {
            withAnimation(.smooth(duration: NotchTabHeightPolicy.animationDuration)) {
                if !lyricsEnabled {
                    // The button is the quickest way to turn lyrics on at all.
                    lyricsEnabled = true
                    expanded = true
                } else {
                    expanded.toggle()
                }
            }
        } label: {
            Image(systemName: isOn ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? appearance.accentColor : Color.secondary)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(Color.white.opacity(isOn ? 0.14 : 0)))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Hide lyrics" : "Show lyrics")
        .accessibilityLabel(isOn ? "Hide lyrics" : "Show lyrics")
    }
}

/// Three lines under the player: the one before, the one being sung (with a
/// sweep that follows the music) and the one coming up.
struct MusicLyricsPanel: View {
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    /// Extra height the Music tab takes while the panel is open.
    static let height: CGFloat = 64

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying)) { context in
            let lines = music.syncedLyrics
            let position = LyricsKaraokePolicy.position(
                timestamps: lines.map(\.timestamp),
                texts: lines.map(\.text),
                at: music.estimatedPlaybackPosition(at: context.date)
            )
            content(lines: lines, position: position)
        }
        .frame(maxWidth: .infinity, minHeight: Self.height - 8, maxHeight: Self.height - 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: NotchTokens.Radius.card))
        .clipShape(RoundedRectangle(cornerRadius: NotchTokens.Radius.card))
    }

    @ViewBuilder
    private func content(lines: [LyricLine], position: LyricsKaraokePolicy.Position) -> some View {
        if lines.isEmpty {
            let plain = music.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(plain.isEmpty ? "No synced lyrics for this song" : plain)
                .font(.system(size: 12, weight: plain.isEmpty ? .regular : .semibold))
                .foregroundStyle(plain.isEmpty ? Color.secondary : Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let index = position.index ?? -1
            VStack(spacing: 3) {
                lineText(lines, index - 1)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                currentLine(lines, position: position)
                lineText(lines, index + 1)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: position.index)
        }
    }

    private func lineText(_ lines: [LyricLine], _ index: Int) -> some View {
        let text = lines.indices.contains(index) ? lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return Text(text.isEmpty ? " " : text)
            .lineLimit(1)
            .truncationMode(.tail)
            .id("line-\(index)")
    }

    @ViewBuilder
    private func currentLine(_ lines: [LyricLine], position: LyricsKaraokePolicy.Position) -> some View {
        if let index = position.index, lines.indices.contains(index), !position.isInstrumental {
            let text = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            ZStack(alignment: .leading) {
                Text(text).foregroundStyle(.white.opacity(0.45))
                Text(text)
                    .foregroundStyle(accent)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width * position.progress)
                        }
                    }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .id("current-\(index)")
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent.opacity(0.8))
                .symbolEffect(.pulse, isActive: music.isPlaying)
        }
    }

    private var accent: Color {
        Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.75)
    }
}
