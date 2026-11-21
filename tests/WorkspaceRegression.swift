// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

@main
struct WorkspaceRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "WorkspaceRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = WorkspacePolicy
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        func launch(_ id: String, _ date: Date) -> AppLaunch { AppLaunch(bundleID: id, name: id.components(separatedBy: ".").last!, date: date) }

        // Code, Terminal, Slack and Safari opened together around 9 on three days.
        var launches: [AppLaunch] = []
        for day in [16, 17, 19] {
            launches += [launch("com.microsoft.VSCode", at(day, 9, 0)), launch("com.apple.Terminal", at(day, 9, 2)),
                         launch("com.tinyspeck.slackmacgap", at(day, 9, 4)), launch("com.apple.finder", at(day, 9, 5))]
            if day != 17 { launches.append(launch("com.apple.Safari", at(day, 9, 6))) }
        }
        // Noise: a lone app later in the day, and an old pattern outside two weeks.
        launches.append(launch("com.spotify.client", at(18, 15, 0)))
        launches += [launch("a.one", at(1, 9, 0)), launch("a.two", at(1, 9, 1)), launch("a.three", at(1, 9, 2))]

        let suggestion = P.suggestion(launches: launches, existing: [], dismissed: [], now: now, calendar: calendar)
        try require(suggestion != nil, "No suggestion")
        try require(suggestion?.apps.map(\.bundleID) == ["com.microsoft.VSCode", "com.apple.Terminal", "com.tinyspeck.slackmacgap"],
                    "Suggested apps: \(suggestion?.apps.map(\.bundleID) ?? [])")
        try require(suggestion?.days == 3 && suggestion?.hour == 9 && suggestion?.name == "Morning setup", "Suggestion details")
        // Not again once a workspace covers it, or once dismissed.
        try require(P.suggestion(launches: launches, existing: [["com.microsoft.VSCode", "com.apple.Terminal", "com.tinyspeck.slackmacgap", "x"]],
                                 dismissed: [], now: now, calendar: calendar) == nil, "Suggested what a workspace covers")
        try require(P.suggestion(launches: launches, existing: [], dismissed: [suggestion!.key], now: now, calendar: calendar) == nil,
                    "Suggested a dismissed set")
        // Two days is not a habit yet.
        let twoDays = launches.filter { calendar.component(.day, from: $0.date) != 19 }
        try require(P.suggestion(launches: twoDays, existing: [], dismissed: [], now: now, calendar: calendar) == nil, "Suggested after two days")
        try require(P.trimmed(launches, now: now).allSatisfy { $0.date >= now.addingTimeInterval(-14 * 86_400) }, "Old launches kept")

        // Layout frames.
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let halves = P.frames(for: .sideBySide, visible: visible, count: 3)
        try require(halves == [CGRect(x: 0, y: 25, width: 720, height: 875), CGRect(x: 720, y: 25, width: 720, height: 875)], "Halves: \(halves)")
        try require(P.frames(for: .thirds, visible: visible, count: 2).count == 2, "Thirds with two apps")
        try require(P.frames(for: .none, visible: visible, count: 3).isEmpty, "No layout")

        // Done for the day quits only what workspaces opened.
        let quit = P.appsToQuit(launchedByWorkspaces: ["com.microsoft.VSCode", "com.apple.finder", "com.tinyspeck.slackmacgap"],
                                running: ["com.microsoft.VSCode", "com.apple.finder", "com.apple.mail", "own.app"], ownBundleID: "own.app")
        try require(quit == ["com.microsoft.VSCode"], "Apps to quit: \(quit)")

        // Folders open in the workspace's editor.
        var workspace = Workspace(name: "Work")
        workspace.apps = [WorkspaceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"), WorkspaceApp(bundleID: "com.microsoft.VSCode", name: "Code")]
        try require(P.folderOpener(for: workspace) == "com.microsoft.VSCode", "Folder opener")
        try require(P.normalizedURL("github.com")?.absoluteString == "https://github.com", "URL without scheme")
        try require(P.normalizedURL("not a url") == nil && P.normalizedURL("hello") == nil, "Bad URLs accepted")
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        try require(decoded == workspace, "Workspace does not round-trip")
        // Restoring saved windows: titles first, then order.
        let saved = [WorkspaceWindow(frame: CGRect(x: 0, y: 25, width: 700, height: 800), title: "Inbox"),
                     WorkspaceWindow(frame: CGRect(x: 720, y: 25, width: 700, height: 800), title: "Docs"),
                     WorkspaceWindow(frame: CGRect(x: 100, y: 100, width: 500, height: 400), title: nil)]
        let pairs = P.matchWindows(saved: saved, titles: ["Docs", "Untitled", "Inbox"])
        try require(pairs.map(\.saved) == [0, 1, 2] && pairs.map(\.window) == [2, 0, 1], "Window matching: \(pairs)")
        try require(P.matchWindows(saved: saved, titles: ["A"]).count == 1, "Fewer windows than saved")
        // Frames stay where they were, or move onto a screen that exists.
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let onScreen = CGRect(x: 100, y: 50, width: 800, height: 600)
        try require(P.fitted(onScreen, screens: [main]) == onScreen, "On-screen window moved")
        let unplugged = CGRect(x: 2000, y: 100, width: 800, height: 600)
        let moved = P.fitted(unplugged, screens: [main])
        try require(main.contains(moved) && moved.size == unplugged.size, "Off-screen window not brought back: \(moved)")
        let huge = P.fitted(CGRect(x: 0, y: 0, width: 3000, height: 2000), screens: [main])
        try require(huge == main, "Oversized window not fitted: \(huge)")
        // Older workspaces (no windows) still load.
        let old = #"{"bundleID":"com.apple.Safari","name":"Safari"}"#
        let oldApp = try JSONDecoder().decode(WorkspaceApp.self, from: Data(old.utf8))
        try require(oldApp.windows == nil, "Old workspace app did not load")
        // Setups are windows only: apps without a window and web pages are dropped.
        var screen = Workspace(name: "Setup 1")
        screen.layout = .restore
        screen.urls = ["https://mail.google.com", "https://github.com"]
        screen.apps = [WorkspaceApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", windows: [saved[0]]),
                       WorkspaceApp(bundleID: "com.spotify.client", name: "Spotify", windows: [saved[1]]),
                       WorkspaceApp(bundleID: "com.google.Chrome", name: "Chrome", windows: [saved[2]]),
                       WorkspaceApp(bundleID: "com.apple.mail", name: "Mail", windows: [])]
        let cleaned = P.windowsOnlySetup(screen)
        try require(cleaned.apps.map(\.name) == ["Claude", "Spotify", "Chrome"] && cleaned.urls.isEmpty, "Windows-only setup: \(cleaned.apps.map(\.name))")
        var handMade = Workspace(name: "Study")
        handMade.apps = [WorkspaceApp(bundleID: "com.apple.Notes", name: "Notes")]
        handMade.urls = ["https://wikipedia.org"]
        handMade.layout = .sideBySide
        try require(P.windowsOnlySetup(handMade) == handMade, "A setup made by hand was changed")
        try require(P.windowsToOpen(saved: 2, open: 0) == 2 && P.windowsToOpen(saved: 1, open: 3) == 0 && P.windowsToOpen(saved: 9, open: 0) == 4,
                    "Windows to open")
        try require(P.newWindowScript(for: "com.google.Chrome") == #"tell application id "com.google.Chrome" to make new window"#
                    && P.newWindowScript(for: "com.apple.Safari")?.contains("make new document") == true
                    && P.newWindowScript(for: "com.spotify.client") == nil, "New window scripts")
        try require(P.isNewWindowCommand("New Window") && P.isNewWindowCommand("New Window with Profile - Basic")
                    && P.isNewWindowCommand("Nouvelle fenêtre") && P.isNewWindowCommand("Neues Fenster"), "New Window commands")
        try require(!P.isNewWindowCommand("New Private Window") && !P.isNewWindowCommand("New Incognito Window")
                    && !P.isNewWindowCommand("New Tab") && !P.isNewWindowCommand("New Note") && !P.isNewWindowCommand("Window"),
                    "Not new ordinary windows")
        try require(P.preferredNewWindowCommand([("New Window with Profile - Pro", nil), ("New Window with Profile - Basic", "N")]) == 1
                    && P.preferredNewWindowCommand([("New Window", nil)]) == 0 && P.preferredNewWindowCommand([]) == nil, "Preferred command")
        print("Workspaces: OK")
    }
}
