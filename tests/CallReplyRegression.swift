// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct CallReplyRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "CallReplyRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(CallReplyPolicy.directHandle(from: "+1 (555) 123-4567") == "+15551234567", "Phone caller not usable as a handle")
        try require(CallReplyPolicy.directHandle(from: "maya@example.com") == "maya@example.com", "Email caller not usable")
        try require(CallReplyPolicy.directHandle(from: "Maya Park") == nil, "Name treated as a number")
        try require(CallReplyPolicy.directHandle(from: "Room 101") == nil, "Text with digits treated as a number")
        try require(CallReplyPolicy.initials(for: "Maya Park") == "MP", "Initials wrong")
        try require(CallReplyPolicy.initials(for: "khushii") == "K", "Single-name initials wrong")
        try require(CallReplyPolicy.initials(for: "+1 555 0100") == "#", "Number given letters")
        try require(CallReplyPolicy.hue(for: "Maya") == CallReplyPolicy.hue(for: "maya"), "Avatar color not stable")
        let script = CallReplyPolicy.messagesScript(text: "Back \"soon\"", handle: "+15551234567")
        try require(script.contains(#"participant "+15551234567""#) && script.contains(#"send "Back \"soon\"""#), "Messages script not escaped")
        try require(CallReplyPolicy.isFromCaller(caller: "Maya", headline: "Maya"), "Same name not matched")
        try require(CallReplyPolicy.isFromCaller(caller: "Maya", headline: "Maya · Dinner Group"), "Group headline not matched")
        try require(!CallReplyPolicy.isFromCaller(caller: "Ma", headline: "Maya"), "Partial name matched")
        try require(!CallReplyPolicy.presets.isEmpty, "No quick replies")
        print("Call reply checks passed")
    }
}
