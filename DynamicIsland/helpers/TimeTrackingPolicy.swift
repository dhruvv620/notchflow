// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Pure logic for automatic time tracking (Foundation only, so Build.command
// can check it alone): what kind of time a front app or website is, which
// project a window belongs to, daily totals, the weekly report and the CSV.

enum TimeCategory: String, CaseIterable, Codable, Sendable {
    case coding, writing, design, meetings, learning, communication, browsing, entertainment, social, other

    var title: String {
        switch self {
        case .coding: return "Coding"
        case .writing: return "Writing"
        case .design: return "Design"
        case .meetings: return "Meetings"
        case .learning: return "Learning"
        case .communication: return "Messages & email"
        case .browsing: return "Browsing"
        case .entertainment: return "Entertainment"
        case .social: return "Social"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .writing: return "doc.text"
        case .design: return "paintpalette"
        case .meetings: return "video"
        case .learning: return "book"
        case .communication: return "bubble.left.and.bubble.right"
        case .browsing: return "safari"
        case .entertainment: return "play.rectangle"
        case .social: return "person.2"
        case .other: return "square.grid.2x2"
        }
    }

    /// Counted toward the daily work goal unless the user changes it.
    static let defaultWork: Set<TimeCategory> = [.coding, .writing, .design, .meetings, .learning]
}

/// What was in front at one moment.
struct TimeSample: Equatable, Sendable {
    var bundleID: String
    var appName: String
    var windowTitle: String?
    /// The website's host, when a browser is in front.
    var host: String?
}

/// One day's totals, in seconds. Stored as one small JSON file per day.
struct TimeDayLog: Codable, Equatable, Sendable {
    var day: String
    var categories: [String: Double] = [:]
    /// By app, or by website for browsers ("YouTube", "Xcode").
    var apps: [String: Double] = [:]
    /// The category each entry in `apps` was counted as.
    var appCategories: [String: String] = [:]
    var projects: [String: Double] = [:]
    /// "13|coding" → seconds, for the day's timeline.
    var hours: [String: Double] = [:]

    init(day: String) { self.day = day }

    mutating func add(seconds: Double, category: TimeCategory, label: String, project: String?, hour: Int) {
        guard seconds > 0, seconds.isFinite else { return }
        categories[category.rawValue, default: 0] += seconds
        apps[label, default: 0] += seconds
        appCategories[label] = category.rawValue
        if let project, !project.isEmpty { projects[project, default: 0] += seconds }
        hours["\(hour)|\(category.rawValue)", default: 0] += seconds
    }

    var total: Double { categories.values.reduce(0, +) }

    func work(_ workCategories: Set<TimeCategory>) -> Double {
        workCategories.reduce(0) { $0 + (categories[$1.rawValue] ?? 0) }
    }

    func seconds(_ category: TimeCategory) -> Double { categories[category.rawValue] ?? 0 }

    /// Largest first.
    func topCategories(_ limit: Int) -> [(TimeCategory, Double)] {
        categories.compactMap { key, value in TimeCategory(rawValue: key).map { ($0, value) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit).map { $0 }
    }

    func topApps(_ limit: Int) -> [(String, Double)] {
        apps.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    func topProjects(_ limit: Int) -> [(String, Double)] {
        projects.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// Seconds per category for one hour of the day.
    func hour(_ hour: Int) -> [TimeCategory: Double] {
        var result: [TimeCategory: Double] = [:]
        for (key, value) in hours {
            let parts = key.split(separator: "|")
            guard parts.count == 2, Int(parts[0]) == hour, let category = TimeCategory(rawValue: String(parts[1])) else { continue }
            result[category, default: 0] += value
        }
        return result
    }
}

struct TimeWeekReport: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        let day: String
        let work: Double
        let total: Double
    }
    let days: [Day]
    let workThisWeek: Double
    let workLastWeek: Double
    let bestDay: String?
    /// The non-work app or site that took the most time this week.
    let biggestSink: String?
    let biggestSinkSeconds: Double

    /// +0.25 means 25% more work than the week before; nil without a previous week.
    var change: Double? {
        guard workLastWeek > 60 else { return nil }
        return (workThisWeek - workLastWeek) / workLastWeek
    }
}

enum TimeTrackingPolicy {
    // MARK: Categories

    static let appCategories: [String: TimeCategory] = [
        // Coding
        "com.apple.dt.Xcode": .coding, "com.microsoft.VSCode": .coding, "com.microsoft.VSCodeInsiders": .coding,
        "com.todesktop.230313mzl4w4u92": .coding, "com.exafunction.windsurf": .coding, "dev.zed.Zed": .coding,
        "com.sublimetext.4": .coding, "com.panic.Nova": .coding, "com.apple.Terminal": .coding,
        "com.googlecode.iterm2": .coding, "dev.warp.Warp-Stable": .coding, "com.mitchellh.ghostty": .coding,
        "net.kovidgoyal.kitty": .coding, "com.github.wez.wezterm": .coding, "com.github.GitHubClient": .coding,
        "com.fournova.Tower3": .coding, "com.postmanlabs.mac": .coding, "com.docker.docker": .coding,
        "com.tinyapp.TablePlus": .coding, "com.openai.codex": .coding, "com.anthropic.claudefordesktop": .writing,
        // Writing and notes
        "com.apple.iWork.Pages": .writing, "com.microsoft.Word": .writing, "notion.id": .writing,
        "md.obsidian": .writing, "com.apple.Notes": .writing, "com.ulyssesapp.mac": .writing,
        "pro.writer.mac": .writing, "com.apple.iWork.Keynote": .writing, "com.microsoft.Powerpoint": .writing,
        "com.apple.iWork.Numbers": .writing, "com.microsoft.Excel": .writing, "com.craft.craft": .writing,
        "com.openai.chat": .writing,
        // Design
        "com.figma.Desktop": .design, "com.bohemiancoding.sketch3": .design, "com.adobe.Photoshop": .design,
        "com.adobe.illustrator": .design, "com.seriflabs.affinitydesigner2": .design, "com.pixelmatorteam.pixelmator.x": .design,
        "com.apple.FinalCut": .design, "com.apple.logic10": .design, "com.blackmagic-design.DaVinciResolve": .design,
        // Meetings
        "us.zoom.xos": .meetings, "com.microsoft.teams2": .meetings, "com.microsoft.teams": .meetings,
        "com.apple.FaceTime": .meetings, "com.cisco.webexmeetingsapp": .meetings,
        // Messages and email
        "com.apple.mail": .communication, "com.microsoft.Outlook": .communication, "com.readdle.SparkDesktop": .communication,
        "com.tinyspeck.slackmacgap": .communication, "com.hnc.Discord": .communication, "com.apple.MobileSMS": .communication,
        "net.whatsapp.WhatsApp": .communication, "ru.keepcoder.Telegram": .communication, "com.superhuman.electron": .communication,
        // Entertainment and social
        "com.apple.TV": .entertainment, "com.netflix.Netflix": .entertainment, "com.apple.Music": .entertainment,
        "com.spotify.client": .entertainment, "com.apple.podcasts": .entertainment, "com.valvesoftware.steam": .entertainment,
        "com.apple.Photos": .other, "com.apple.finder": .other, "com.apple.systempreferences": .other,
    ]

    /// Websites, matched by host and its parent domains.
    static let siteCategories: [String: TimeCategory] = [
        "github.com": .coding, "gitlab.com": .coding, "stackoverflow.com": .coding, "developer.apple.com": .coding,
        "vercel.com": .coding, "localhost": .coding, "127.0.0.1": .coding, "npmjs.com": .coding, "huggingface.co": .coding,
        "docs.google.com": .writing, "notion.so": .writing, "notion.site": .writing, "chatgpt.com": .writing,
        "claude.ai": .writing, "gemini.google.com": .writing, "office.com": .writing, "overleaf.com": .writing,
        "figma.com": .design, "canva.com": .design, "dribbble.com": .design,
        "meet.google.com": .meetings, "zoom.us": .meetings, "teams.microsoft.com": .meetings, "teams.live.com": .meetings,
        "coursera.org": .learning, "udemy.com": .learning, "khanacademy.org": .learning, "wikipedia.org": .learning,
        "edx.org": .learning, "leetcode.com": .learning,
        "mail.google.com": .communication, "outlook.live.com": .communication, "outlook.office.com": .communication,
        "app.slack.com": .communication, "web.whatsapp.com": .communication, "discord.com": .communication,
        "web.telegram.org": .communication, "messenger.com": .communication,
        "youtube.com": .entertainment, "netflix.com": .entertainment, "twitch.tv": .entertainment,
        "primevideo.com": .entertainment, "disneyplus.com": .entertainment, "hotstar.com": .entertainment,
        "open.spotify.com": .entertainment, "music.youtube.com": .entertainment,
        "x.com": .social, "twitter.com": .social, "instagram.com": .social, "facebook.com": .social,
        "reddit.com": .social, "tiktok.com": .social, "linkedin.com": .social, "threads.net": .social,
        "news.ycombinator.com": .social, "pinterest.com": .social, "snapchat.com": .social,
    ]

    /// Friendly names for common sites.
    static let siteNames: [String: String] = [
        "youtube.com": "YouTube", "github.com": "GitHub", "x.com": "X", "twitter.com": "X", "reddit.com": "Reddit",
        "instagram.com": "Instagram", "facebook.com": "Facebook", "linkedin.com": "LinkedIn", "netflix.com": "Netflix",
        "mail.google.com": "Gmail", "docs.google.com": "Google Docs", "meet.google.com": "Google Meet",
        "stackoverflow.com": "Stack Overflow", "chatgpt.com": "ChatGPT", "claude.ai": "Claude", "notion.so": "Notion",
        "figma.com": "Figma", "web.whatsapp.com": "WhatsApp Web", "news.ycombinator.com": "Hacker News",
        "twitch.tv": "Twitch", "tiktok.com": "TikTok", "app.slack.com": "Slack", "music.youtube.com": "YouTube Music",
    ]

    /// "www.youtube.com" → "youtube.com".
    static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased().trimmingCharacters(in: .whitespaces), !host.isEmpty else { return nil }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        return host
    }

    /// The table entry for a host or its closest parent domain.
    static func lookup<T>(_ host: String, in table: [String: T]) -> T? {
        var candidate = host
        while true {
            if let value = table[candidate] { return value }
            guard let dot = candidate.firstIndex(of: ".") else { return nil }
            candidate = String(candidate[candidate.index(after: dot)...])
            if !candidate.contains(".") && candidate != "localhost" { return nil }
        }
    }

    /// User overrides are keyed by bundle id or host.
    static func category(for sample: TimeSample, overrides: [String: TimeCategory] = [:]) -> TimeCategory {
        if let host = normalizedHost(sample.host) {
            if let override = lookup(host, in: overrides) { return override }
            return lookup(host, in: siteCategories) ?? .browsing
        }
        if let override = overrides[sample.bundleID] { return override }
        if let known = appCategories[sample.bundleID] { return known }
        let id = sample.bundleID.lowercased()
        if id.hasPrefix("com.jetbrains.") || id.contains("android.studio") { return .coding }
        if id.hasPrefix("com.adobe.") { return .design }
        if id.hasPrefix("com.microsoft.office") { return .writing }
        return .other
    }

    /// What the time is listed under: the site for browsers, otherwise the app.
    static func label(for sample: TimeSample) -> String {
        if let host = normalizedHost(sample.host) {
            return lookup(host, in: siteNames) ?? host
        }
        let name = sample.appName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? sample.bundleID : name
    }

    // MARK: Projects

    static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "dev.zed.Zed", "com.sublimetext.4", "com.panic.Nova",
    ]
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm",
    ]
    private static let notProjects: Set<String> = [
        "welcome", "untitled", "settings", "preferences", "extensions", "get started", "new tab", "zsh", "-zsh",
        "bash", "-bash", "fish", "login", "terminal", "home", "~", "desktop", "downloads", "documents",
    ]

    /// The project a window belongs to. Known project names (from agent
    /// sessions and Settings) win; otherwise editors and terminals are read
    /// by their usual title formats.
    static func project(in title: String?, bundleID: String, known: [String]) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let lower = title.lowercased()
        let names = known.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 2 }
        for name in names.sorted(by: { $0.count > $1.count }) where containsWord(name.lowercased(), in: lower) {
            return name
        }
        let parts = title.components(separatedBy: " — ").flatMap { $0.components(separatedBy: " – ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if terminals.contains(bundleID) {
            if let range = title.range(of: "~/") {
                let path = title[range.upperBound...].prefix { $0 != " " && $0 != "—" && $0 != ":" }
                if let first = path.split(separator: "/").first { return clean(String(first)) }
            }
            return parts.first.flatMap(clean)
        }
        if bundleID == "com.apple.dt.Xcode" || bundleID.hasPrefix("com.jetbrains.") {
            return parts.first.flatMap(clean)
        }
        if editors.contains(bundleID) {
            // "ContentView.swift — notchflow" (and maybe " — Visual Studio Code")
            let candidates = parts.dropFirst().filter { !$0.lowercased().contains("visual studio code") && $0.lowercased() != "cursor" }
            return candidates.first.flatMap(clean) ?? (parts.count == 1 ? clean(parts[0]) : nil)
        }
        return nil
    }

    private static func clean(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bracket = value.range(of: " [") { value = String(value[..<bracket.lowerBound]) }
        if let colon = value.firstIndex(of: ":"), value[..<colon].contains("@") { value = String(value[value.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
        if value.hasPrefix("~/") { value = String(value.dropFirst(2)).split(separator: "/").first.map(String.init) ?? "" }
        guard !value.isEmpty, value.count <= 60, !notProjects.contains(value.lowercased()) else { return nil }
        // A file name ("ContentView.swift") is not a project.
        if let dot = value.lastIndex(of: "."), value.distance(from: dot, to: value.endIndex) <= 6, !value.contains(" ") { return nil }
        return value
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let afterOK = range.upperBound == text.endIndex || !isWordCharacter(text[range.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    // MARK: Counting

    /// Time stops counting after this much idle time, except where people
    /// watch or listen without touching anything.
    static func idleLimit(for category: TimeCategory) -> TimeInterval {
        category == .meetings || category == .entertainment ? 30 * 60 : 5 * 60
    }

    static func shouldCount(idleSeconds: TimeInterval, category: TimeCategory, locked: Bool) -> Bool {
        !locked && idleSeconds < idleLimit(for: category)
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Reports

    static func weekReport(logs: [TimeDayLog], endingOn today: Date, work: Set<TimeCategory>,
                           calendar: Calendar = .current) -> TimeWeekReport {
        let byDay = Dictionary(logs.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        func key(_ offset: Int) -> String {
            dayKey(calendar.date(byAdding: .day, value: -offset, to: today) ?? today, calendar: calendar)
        }
        let thisWeek = (0..<7).reversed().map { key($0) }
        let lastWeek = (7..<14).map { key($0) }
        let days = thisWeek.map { day -> TimeWeekReport.Day in
            let log = byDay[day]
            return TimeWeekReport.Day(day: day, work: log?.work(work) ?? 0, total: log?.total ?? 0)
        }
        let workThis = days.reduce(0) { $0 + $1.work }
        let workLast = lastWeek.reduce(0) { $0 + (byDay[$1]?.work(work) ?? 0) }
        let best = days.filter { $0.work > 0 }.max { $0.work < $1.work }?.day
        var sinks: [String: Double] = [:]
        for day in thisWeek {
            guard let log = byDay[day] else { continue }
            for (label, seconds) in log.apps {
                guard let raw = log.appCategories[label], let category = TimeCategory(rawValue: raw),
                      !work.contains(category), category != .other else { continue }
                sinks[label, default: 0] += seconds
            }
        }
        let sink = sinks.max { $0.value < $1.value }
        return TimeWeekReport(days: days, workThisWeek: workThis, workLastWeek: workLast, bestDay: best,
                              biggestSink: sink?.key, biggestSinkSeconds: sink?.value ?? 0)
    }

    /// Hours per project per day, for invoicing.
    static func csv(logs: [TimeDayLog]) -> String {
        var lines = ["Date,Project,Hours"]
        for log in logs.sorted(by: { $0.day < $1.day }) {
            for (project, seconds) in log.projects.sorted(by: { $0.key < $1.key }) where seconds >= 60 {
                lines.append("\(log.day),\(csvField(project)),\(String(format: "%.2f", seconds / 3600))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "3h 10m", "45m", "<1m".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 { return seconds > 0 ? "<1m" : "0m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "3h 10m coding · 50m messages & email · 35m entertainment"
    static func summaryLine(_ log: TimeDayLog, limit: Int = 4) -> String {
        let parts = log.topCategories(limit).filter { $0.1 >= 60 }.map { "\(duration($0.1)) \($0.0.title.lowercased())" }
        return parts.isEmpty ? "Nothing tracked yet today" : parts.joined(separator: " · ")
    }

    /// The work categories from their stored names.
    static func workCategories(from names: [String]) -> Set<TimeCategory> {
        let parsed = Set(names.compactMap(TimeCategory.init(rawValue:)))
        return parsed.isEmpty ? TimeCategory.defaultWork : parsed
    }
}
