// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct WelcomeChimeRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "WelcomeChimeRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let wav = WelcomeChimePolicy.wavData()
        let frames = Int(WelcomeChimePolicy.duration * Double(WelcomeChimePolicy.sampleRate))
        try require(wav.count == 44 + frames * 2, "Unexpected WAV size \(wav.count)")
        try require(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF", "Missing RIFF header")
        try require(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE", "Missing WAVE header")
        try require(String(decoding: wav[36..<40], as: UTF8.self) == "data", "Missing data chunk")

        // Audible, never clipping, and silent at both ends (no clicks).
        var peak = 0.0
        var t = 0.0
        while t < WelcomeChimePolicy.duration {
            peak = max(peak, abs(WelcomeChimePolicy.sample(at: t)))
            t += 1.0 / 8000
        }
        try require(peak > 0.08 && peak < 0.95, "Peak out of range: \(peak)")
        try require(abs(WelcomeChimePolicy.sample(at: 0)) < 0.001, "Starts with a click")
        try require(abs(WelcomeChimePolicy.sample(at: WelcomeChimePolicy.duration)) < 0.001, "Ends with a click")
        try require(zip(WelcomeChimePolicy.notes, WelcomeChimePolicy.notes.dropFirst()).allSatisfy { $0.start < $1.start && $0.frequency < $1.frequency },
                    "Notes should rise in time and pitch")
        print("Welcome chime: OK")
    }
}
