// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The welcome chime that plays while "hello" writes itself on first launch:
/// a soft rising arpeggio, synthesized as a WAV in memory so the app ships no
/// extra sound file. Foundation only, so Build.command can check it alone.
enum WelcomeChimePolicy {
    struct Note: Equatable {
        /// Seconds from the start.
        let start: Double
        /// Hertz.
        let frequency: Double
        /// 0...1 before the overall volume.
        let level: Double
    }

    static let sampleRate = 44_100
    static let duration = 3.4
    static let volume = 0.22

    /// G5, C6, E6, G6, timed with the letters, then a high C to finish.
    static let notes: [Note] = [
        Note(start: 0.00, frequency: 783.99, level: 0.75),
        Note(start: 0.42, frequency: 1046.50, level: 0.70),
        Note(start: 0.84, frequency: 1318.51, level: 0.65),
        Note(start: 1.26, frequency: 1567.98, level: 0.60),
        Note(start: 1.95, frequency: 2093.00, level: 0.45),
    ]

    /// One sample in -1...1: each note is a sine with soft overtones, a short
    /// attack and an exponential fade, like a small bell.
    static func sample(at time: Double) -> Double {
        var value = 0.0
        for note in notes where time >= note.start {
            let t = time - note.start
            let attack = min(1, t / 0.012)
            let envelope = attack * exp(-t / 0.55)
            guard envelope > 0.0005 else { continue }
            let phase = 2 * Double.pi * note.frequency * t
            let tone = sin(phase) + 0.28 * sin(2 * phase) * exp(-t / 0.25) + 0.08 * sin(3 * phase) * exp(-t / 0.15)
            value += note.level * envelope * tone
        }
        // Fade the last 0.3 s so the file never ends on a click.
        let tail = max(0, min(1, (duration - time) / 0.3))
        return max(-1, min(1, value * volume * tail))
    }

    /// 16-bit mono PCM in a WAV container.
    static func wavData() -> Data {
        let count = Int(duration * Double(sampleRate))
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let value = Int16((sample(at: Double(index) / Double(sampleRate)) * Double(Int16.max)).rounded())
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append32(UInt32(36 + pcm.count))
        append("WAVE")
        append("fmt ")
        append32(16)                         // PCM header size
        append16(1)                          // PCM
        append16(1)                          // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))     // bytes per second
        append16(2)                          // bytes per frame
        append16(16)                         // bits per sample
        append("data")
        append32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
