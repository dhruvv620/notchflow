// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct TerminalCommandRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "TerminalCommandRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = TerminalCommandPolicy
        try require(P.programName("-zsh") == "zsh" && P.programName("/usr/local/bin/NPM") == "npm" && P.programName(" git ") == "git", "Names")
        try require(P.shouldNotify(command: "npm", duration: 42, threshold: 10, isWatching: false, enabled: true), "Long build: tell me")
        try require(!P.shouldNotify(command: "npm", duration: 4, threshold: 10, isWatching: false, enabled: true), "Quick: no")
        try require(!P.shouldNotify(command: "npm", duration: 42, threshold: 10, isWatching: true, enabled: true), "Watching it: no")
        try require(!P.shouldNotify(command: "npm", duration: 42, threshold: 10, isWatching: false, enabled: false), "Off: no")
        try require(!P.shouldNotify(command: "nvim", duration: 900, threshold: 10, isWatching: false, enabled: true)
                    && !P.shouldNotify(command: "ssh", duration: 900, threshold: 10, isWatching: false, enabled: true)
                    && !P.shouldNotify(command: "claude", duration: 900, threshold: 10, isWatching: false, enabled: true), "Interactive: no")
        try require(P.durationText(45) == "45s" && P.durationText(133) == "2m 13s" && P.durationText(3840) == "1h 4m", "Durations")
        let message = P.message(command: "cargo", duration: 75, session: "Terminal 2")
        try require(message.title == "cargo finished" && message.body == "Terminal 2 · after 1m 15s", "Message")
        try require(P.tabTitle("", index: 0) == "Terminal" && P.tabTitle("Terminal", index: 2) == "Terminal 3"
                    && P.tabTitle("dv@mac: ~/notchflow (main) building things", index: 0).count == 24, "Tab titles")
        let iterm = P.openScript(bundleID: "com.googlecode.iterm2", directory: "/Users/me/it's here") ?? ""
        try require(iterm.contains("create window with default profile") && iterm.contains(#"write text "cd '/Users/me/it'\\''s here'""#),
                    "iTerm script: \(iterm)")
        try require(P.openScript(bundleID: "com.apple.Terminal", directory: "/tmp")?.contains("do script \"cd '/tmp'\"") == true
                    && P.openScript(bundleID: "com.mitchellh.ghostty", directory: "/tmp") == nil, "Other apps")
        print("Terminal commands: OK")
    }
}
