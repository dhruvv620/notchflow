// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct CuelyVoiceFollowRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "CuelyVoiceFollowRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let text = """
        Hello everyone, and welcome back to the channel.
        Today we're going to build a teleprompter that listens to your voice.
        It follows along as you read, so you never lose your place.
        """
        let script = CuelyVoiceFollowPolicy.words(in: text)
        try require(script.first?.normalized == "hello" && script[3].normalized == "welcome", "Words not split")
        try require(script.contains { $0.normalized == "were" }, "Apostrophe not folded")
        try require((text as NSString).substring(with: script[1].range) == "everyone", "Ranges wrong")

        func spoken(_ s: String) -> [String] { CuelyVoiceFollowPolicy.spokenWords(in: s) }
        let i1 = CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("hello everyone and welcome"), cursor: 0)
        try require(i1 == 4, "Start not followed: \(String(describing: i1))")
        let i2 = CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("today we are going to build a teleprompter"), cursor: 8)
        try require(i2 == 15, "Recognizer slips ('we are') not tolerated: \(String(describing: i2))")
        let i3 = CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("so you never lose"), cursor: 15)
        try require(i3 == script.firstIndex { $0.normalized == "lose" }.map { $0 + 1 }, "Skipping ahead within reach failed")
        try require(CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("pizza tonight maybe"), cursor: 5) == nil, "Unrelated speech moved the cursor")
        try require(CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("the"), cursor: 5) == nil, "A filler word moved the cursor")
        try require(CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("welcome"), cursor: 3) == 4, "Single next word not followed")
        // Re-reading an earlier sentence needs more words.
        try require(CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("welcome back"), cursor: 16) == nil, "Weak backward jump accepted")
        try require(CuelyVoiceFollowPolicy.advance(script: script, spoken: spoken("and welcome back to the channel"), cursor: 16) == 8, "Strong re-read not followed")
        try require(CuelyVoiceFollowPolicy.matches("teleprompters", "teleprompter") && CuelyVoiceFollowPolicy.matches("chanel", "channel"), "Fuzzy match too strict")
        try require(!CuelyVoiceFollowPolicy.matches("cat", "car"), "Fuzzy match too loose")
        try require(CuelyVoiceFollowPolicy.wordIndex(atCharacter: script[3].range.location + 1, in: script) == 3, "Click to jump wrong")
        try require(CuelyPanelSize.extraLarge.next == .regular && CuelyPanelSize.large.extraHeight > 0, "Panel sizes wrong")
        // Read the whole script aloud, word by word, with a few recognition mistakes.
        var heard: [String] = []
        var cursor = 0
        var maxJump = 0
        for (index, word) in script.enumerated() {
            heard.append(index % 7 == 3 ? "um" : (index % 11 == 5 ? word.normalized + "s" : word.normalized))
            if let next = CuelyVoiceFollowPolicy.advance(script: script, spoken: Array(heard.suffix(8)), cursor: cursor) {
                maxJump = max(maxJump, next - cursor)
                cursor = next
            }
        }
        try require(cursor >= script.count - 1, "Read-through stalled at \(cursor) of \(script.count)")
        try require(maxJump <= 3, "Cursor jumped ahead by \(maxJump) words")
        print("Cuely voice-follow checks passed")
    }
}
