// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct LyricsKaraokeRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "LyricsKaraokeRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let times: [TimeInterval] = [10, 14, 30, 31]
        let texts = ["First line", "Second line", "", "Last line"]
        typealias P = LyricsKaraokePolicy
        try require(P.position(timestamps: times, texts: texts, at: 5).index == nil, "A line shown before the first one")
        let first = P.position(timestamps: times, texts: texts, at: 12)
        try require(first.index == 0 && abs(first.progress - 0.5) < 0.001, "Sweep not halfway: \(first)")
        let capped = P.position(timestamps: times, texts: texts, at: 20)
        try require(capped.index == 1 && capped.progress == 0.75, "Long gap not capped to the maximum sweep: \(capped)")
        try require(P.position(timestamps: times, texts: texts, at: 30.5).isInstrumental, "Empty line not instrumental")
        let last = P.position(timestamps: times, texts: texts, at: 40)
        try require(last.index == 3 && last.progress == 1, "Last line not finished")
        try require(P.position(timestamps: [], texts: [], at: 3).index == nil, "Empty lyrics gave a line")
        try require(P.position(timestamps: times, texts: ["only one"], at: 12).index == nil, "Mismatched input accepted")
        try require(P.position(timestamps: times, texts: texts, at: .nan).index == nil, "NaN time accepted")
        print("Lyrics checks passed")
    }
}
