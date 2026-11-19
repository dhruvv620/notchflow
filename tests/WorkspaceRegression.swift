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
        print("Workspaces: OK")
    }
}
