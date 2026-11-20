// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct SmartToolsRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "SmartToolsRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        // Distraction meter
        let sites = FocusGuardPolicy.list(from: "YouTube.com, x.com\nreddit.com, x.com")
        try require(sites == ["youtube.com", "x.com", "reddit.com"], "Site list not normalized")
        try require(FocusGuardPolicy.isDistractingHost("m.youtube.com", sites: sites), "Subdomain not matched")
        try require(!FocusGuardPolicy.isDistractingHost("notyoutube.com", sites: sites), "Lookalike matched")
        try require(!FocusGuardPolicy.isDistractingHost("box.com", sites: sites), "x.com suffix matched box.com")
        try require(FocusGuardPolicy.isDistracting(bundleID: "COM.HNC.DISCORD", url: nil, apps: ["com.hnc.discord"], sites: []), "App not matched")
        try require(FocusGuardPolicy.offTrackLabel(seconds: 185) == "3 min off track" && FocusGuardPolicy.offTrackLabel(seconds: 45) == "45s off track", "Off-track label wrong")

        // Copy-to-action
        func first(_ text: String) -> CopyAction? { CopyActionPolicy.detect(text).first }
        if case .trackPackage(_, let carrier, _)? = first("1Z 999 AA1 01 2345 6784") { try require(carrier == "UPS", "UPS carrier") } else { try require(false, "UPS not detected") }
        if case .trackPackage(_, let carrier, _)? = first("TBA123456789012") { try require(carrier == "Amazon", "Amazon carrier") } else { try require(false, "Amazon not detected") }
        if case .flight(let code, _)? = first("UA 123") { try require(code == "UA123", "Flight code") } else { try require(false, "Flight not detected") }
        try require(first("= hello") == nil && first("Hello there, how are you?") == nil, "Ordinary text gave an action")
        try require(CopyActionPolicy.calculate("12*7+3") == "87", "Arithmetic wrong")
        try require(CopyActionPolicy.calculate("(1+2)^2/4") == "2.25", "Parentheses/power wrong")
        try require(CopyActionPolicy.calculate("1,200 × 3") == "3600", "Separators/× not handled")
        try require(CopyActionPolicy.calculate("5/0") == nil && CopyActionPolicy.calculate("2+") == nil && CopyActionPolicy.calculate("42") == nil, "Bad maths accepted")
        try require(CopyActionPolicy.calculate("2025-11-18") != nil, "Dates are arithmetic by design here")
        try require(first("sam@example.com") == .email(address: "sam@example.com"), "Email not detected")
        try require(first("+1 (555) 123-4567") == .call(number: "+15551234567"), "Phone not detected")
        try require(CopyActionPolicy.detect(String(repeating: "a", count: 300)).isEmpty, "Long text inspected")

        // Smart replies
        let prompt = SmartReplyPolicy.prompt(sender: "Selene", message: "Dinner at 8?", context: ["Selene: hey"])
        try require(prompt.user.contains("Message from Selene: Dinner at 8?") && prompt.user.contains("Selene: hey")
                    && prompt.system.contains("Hinglish"), "Reply prompt wrong")
        let response = #"{"choices":[{"message":{"content":"<think>She wants dinner.</think>\n```json\n[\"Sounds good!\", \"Can we do 8:30?\", \"Sorry, can't tonight\"]\n```"}}]}"#
        try require(SmartReplyPolicy.suggestions(fromResponse: Data(response.utf8)) == ["Sounds good!", "Can we do 8:30?", "Sorry, can't tonight"], "Suggestions not parsed")
        try require(SmartReplyPolicy.suggestions(fromText: "1. Yes!\n2. Maybe later\n- No thanks\n4. Extra") == ["Yes!", "Maybe later", "No thanks"], "Line fallback wrong")
        try require(SmartReplyPolicy.suggestions(fromResponse: Data("{}".utf8)).isEmpty, "Empty response gave suggestions")

        // Build watcher
        let runs = #"{"workflow_runs":[{"id":1,"name":"CI","status":"in_progress","head_branch":"main","html_url":"https://github.com/a/b/actions/runs/1","updated_at":"2026-11-18T10:00:00Z"},{"id":2,"name":"Deploy","status":"completed","conclusion":"failure"},{"id":3,"name":"Lint","status":"completed","conclusion":"success"}]}"#
        let parsed = BuildWatchPolicy.githubRuns(from: Data(runs.utf8), repository: "a/b")
        try require(parsed.map(\.state) == [.running, .failure, .success] && parsed[0].detail == "a/b · main", "GitHub runs misread")
        let before = [WatchedRun(id: "gh-1", title: "CI", detail: "", state: .running, url: nil, updatedAt: .distantPast)]
        let after = [WatchedRun(id: "gh-1", title: "CI", detail: "", state: .success, url: nil, updatedAt: .distantPast),
                     WatchedRun(id: "gh-9", title: "Old", detail: "", state: .failure, url: nil, updatedAt: .distantPast)]
        try require(BuildWatchPolicy.newlyFinished(previous: before, current: after).map(\.id) == ["gh-1"], "Only runs seen running should be announced")
        let job = BuildWatchPolicy.terminalJob(from: Data(#"{"name":"npm test","status":"done","code":1,"started":1,"ended":5}"#.utf8), id: "x")
        try require(job?.state == .failure && job?.detail == "Exited with 1", "Terminal job misread")
        try require(BuildWatchPolicy.repositories(from: "dhruvv620/notchflow, bad repo, a/b") == ["dhruvv620/notchflow", "a/b"], "Repository list wrong")
        try require(BuildWatchPolicy.shellFunction.contains("NotchFlow/Jobs"), "Shell function missing the jobs folder")
        print("Smart tools checks passed")
    }
}
