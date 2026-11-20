// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// While music with synced lyrics plays, show the sung line under the closed notch.
    static let showLyricsUnderNotch = Key<Bool>("showLyricsUnderNotch", default: true)
}

/// The line being sung, under the closed notch, with a highlight that sweeps
/// across it in time with the music.
struct ClosedNotchLyricsLine: View {
    let width: CGFloat
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var energy = EnergySaver.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    static let height: CGFloat = 26

    var body: some View {
        // 30 fps is plenty for a sweep; 10 on battery saver (Optimizer).
        TimelineView(.animation(minimumInterval: 1.0 / EnergyPolicy.lyricsFrameRate(switches: energy.switches, conditions: energy.conditions), paused: !music.isPlaying)) { context in
            let lines = music.syncedLyrics
            let position = LyricsKaraokePolicy.position(
                timestamps: lines.map(\.timestamp),
                texts: lines.map(\.text),
                at: music.estimatedPlaybackPosition(at: context.date)
            )
            line(for: position, lines: lines)
                .frame(width: max(0, width - 24), height: Self.height - 6)
                .padding(.bottom, 6)
                .animation(.easeOut(duration: 0.2), value: position.index)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func line(for position: LyricsKaraokePolicy.Position, lines: [LyricLine]) -> some View {
        if let index = position.index, !position.isInstrumental, lines.indices.contains(index) {
            let text = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            ZStack(alignment: .leading) {
                Text(text)
                    .foregroundStyle(.white.opacity(0.4))
                Text(text)
                    .foregroundStyle(accent)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width * position.progress)
                        }
                    }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .id(index)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent.opacity(0.7))
                .symbolEffect(.pulse, isActive: music.isPlaying)
        }
    }

    private var accent: Color {
        Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.75)
    }
}
