// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct TimeTrackingRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "TimeTrackingRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = TimeTrackingPolicy

        // Categories: apps, sites (with subdomains), unknowns and overrides.
        func sample(_ id: String, _ name: String = "App", title: String? = nil, host: String? = nil) -> TimeSample {
            TimeSample(bundleID: id, appName: name, windowTitle: title, host: host)
        }
        try require(P.category(for: sample("com.apple.dt.Xcode")) == .coding, "Xcode not coding")
        try require(P.category(for: sample("com.jetbrains.intellij")) == .coding, "JetBrains not coding")
        try require(P.category(for: sample("com.apple.Safari", host: "www.youtube.com")) == .entertainment, "YouTube not entertainment")
        try require(P.category(for: sample("com.google.Chrome", host: "gist.github.com")) == .coding, "Subdomain of github not coding")
        try require(P.category(for: sample("com.google.Chrome", host: "example.org")) == .browsing, "Unknown site not browsing")
        try require(P.category(for: sample("com.unknown.app")) == .other, "Unknown app not other")
        try require(P.category(for: sample("com.apple.Safari", host: "reddit.com"), overrides: ["reddit.com": .learning]) == .learning, "Override ignored")
        try require(P.label(for: sample("com.apple.Safari", "Safari", host: "www.youtube.com")) == "YouTube", "Site label wrong")
        try require(P.label(for: sample("com.apple.Safari", "Safari", host: "example.org")) == "example.org", "Unknown site label wrong")
        try require(P.label(for: sample("com.apple.dt.Xcode", "Xcode")) == "Xcode", "App label wrong")

        // Projects: known names first, then editor and terminal title formats.
        try require(P.project(in: "notchflow — ContentView.swift", bundleID: "com.apple.dt.Xcode", known: []) == "notchflow", "Xcode project")
        try require(P.project(in: "ContentView.swift — notchflow", bundleID: "com.microsoft.VSCode", known: []) == "notchflow", "VS Code project")
        try require(P.project(in: "app.tsx — website — Visual Studio Code", bundleID: "com.microsoft.VSCode", known: []) == "website", "VS Code with app name")
        try require(P.project(in: "dv@MacBook: ~/notchflow/DynamicIsland", bundleID: "com.apple.Terminal", known: []) == "notchflow", "Terminal path")
        try require(P.project(in: "-zsh", bundleID: "com.apple.Terminal", known: []) == nil, "Shell name taken as project")
        try require(P.project(in: "Fix the build in NotchFlow · GitHub", bundleID: "com.apple.Safari", known: ["notchflow"]) == "notchflow", "Known name in a browser title")
        try require(P.project(in: "notchflowkit docs", bundleID: "com.apple.Safari", known: ["notchflow"]) == nil, "Known name matched inside a longer word")
        try require(P.project(in: "Welcome", bundleID: "com.microsoft.VSCode", known: []) == nil, "Welcome taken as project")
        try require(P.project(in: "Inbox", bundleID: "com.apple.mail", known: []) == nil, "Mail window taken as project")

        // Counting stops when idle, but videos and calls are allowed longer.
        try require(P.shouldCount(idleSeconds: 60, category: .coding, locked: false), "Active coding not counted")
        try require(!P.shouldCount(idleSeconds: 400, category: .coding, locked: false), "Idle coding counted")
        try require(P.shouldCount(idleSeconds: 900, category: .entertainment, locked: false), "Watching a video stopped counting")
        try require(!P.shouldCount(idleSeconds: 0, category: .coding, locked: true), "Counted while locked")

        // Day logs and summaries.
        var log = TimeDayLog(day: "2026-11-19")
        log.add(seconds: 2 * 3600, category: .coding, label: "Xcode", project: "notchflow", hour: 10)
        log.add(seconds: 40 * 60, category: .coding, label: "Terminal", project: "notchflow", hour: 11)
        log.add(seconds: 50 * 60, category: .communication, label: "Slack", project: nil, hour: 11)
        log.add(seconds: 35 * 60, category: .entertainment, label: "YouTube", project: nil, hour: 13)
        try require(log.work(TimeCategory.defaultWork) == 2 * 3600 + 40 * 60, "Work total wrong")
        try require(log.topProjects(1).first?.0 == "notchflow" && log.topProjects(1).first?.1 == 2 * 3600 + 40 * 60, "Project total wrong")
        try require(P.summaryLine(log) == "2h 40m coding · 50m messages & email · 35m entertainment", "Summary: \(P.summaryLine(log))")
        try require(log.hour(11)[.coding] == 40 * 60 && log.hour(11)[.communication] == 50 * 60, "Hourly split wrong")
        try require(P.duration(0) == "0m" && P.duration(20) == "<1m" && P.duration(45 * 60) == "45m" && P.duration(3 * 3600) == "3h", "Durations wrong")
        let encoded = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(TimeDayLog.self, from: encoded)
        try require(decoded == log, "Day log does not round-trip")

        // Weekly report against the week before.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 17))!
        var monday = TimeDayLog(day: "2026-11-16"); monday.add(seconds: 5 * 3600, category: .coding, label: "Xcode", project: "a", hour: 9)
        var friday = TimeDayLog(day: "2026-11-20"); friday.add(seconds: 2 * 3600, category: .writing, label: "Pages", project: nil, hour: 9)
        friday.add(seconds: 3600, category: .social, label: "X", project: nil, hour: 12)
        var older = TimeDayLog(day: "2026-11-10"); older.add(seconds: 4 * 3600, category: .coding, label: "Xcode", project: "a", hour: 9)
        let report = P.weekReport(logs: [monday, friday, older], endingOn: today, work: TimeCategory.defaultWork, calendar: calendar)
        try require(report.days.count == 7 && report.days.last?.day == "2026-11-20", "Week days wrong")
        try require(report.workThisWeek == 7 * 3600 && report.workLastWeek == 4 * 3600, "Week totals wrong")
        try require(report.bestDay == "2026-11-16", "Best day wrong")
        try require(report.biggestSink == "X" && report.biggestSinkSeconds == 3600, "Biggest sink wrong")
        try require(abs((report.change ?? 0) - 0.75) < 0.0001, "Change wrong: \(String(describing: report.change))")

        // CSV for invoicing.
        var weird = TimeDayLog(day: "2026-11-18"); weird.add(seconds: 5400, category: .coding, label: "Xcode", project: "Acme, Inc", hour: 9)
        let csv = P.csv(logs: [log, weird])
        try require(csv == "Date,Project,Hours\n2026-11-18,\"Acme, Inc\",1.50\n2026-11-19,notchflow,2.67\n", "CSV: \(csv)")
        try require(P.workCategories(from: []) == TimeCategory.defaultWork && P.workCategories(from: ["coding"]) == [.coding], "Work categories parsing")
        print("Time tracking: OK")
    }
}
