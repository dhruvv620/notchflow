// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A window's place on screen, in Accessibility coordinates (origin at the
/// top left of the main display).
struct WorkspaceWindow: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var title: String?

    init(frame: CGRect, title: String?) {
        x = Double(frame.minX); y = Double(frame.minY)
        width = Double(frame.width); height = Double(frame.height)
        self.title = title
    }

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// An app in a workspace.
struct WorkspaceApp: Codable, Equatable, Hashable, Sendable {
    let bundleID: String
    var name: String
    /// Its windows' positions and sizes, when the workspace was saved from
    /// what was open (nil in older workspaces).
    var windows: [WorkspaceWindow]? = nil
}

/// A saved setup: apps, pages and folders to open, and how to arrange them.
struct Workspace: Codable, Equatable, Identifiable, Sendable {
    enum Layout: String, Codable, CaseIterable, Sendable {
        case none, sideBySide, thirds, restore

        var title: String {
            switch self {
            case .none: return "Leave as they are"
            case .restore: return "Exactly as saved"
            case .sideBySide: return "First two side by side"
            case .thirds: return "First three in columns"
            }
        }
    }

    var id = UUID()
    var name: String
    var symbol: String = "briefcase.fill"
    var apps: [WorkspaceApp] = []
    /// Web pages, opened in the default browser.
    var urls: [String] = []
    /// Folders, opened in the workspace's editor when it has one, otherwise Finder.
    var folders: [String] = []
    /// A folder to open a terminal window in.
    var terminalFolder: String = ""
    var layout: Layout = .none
    /// Run the "Focus on" shortcut (Do Not Disturb).
    var turnOnFocus = false
    var startPomodoro = false
    /// Start music; with a playlist name, that Apple Music playlist.
    var playMusic = false
    var playlist: String = ""
    var hideOtherApps = false

    var isEmpty: Bool { apps.isEmpty && urls.isEmpty && folders.isEmpty && terminalFolder.isEmpty }
}

/// An app launch, for learning which apps you open together.
struct AppLaunch: Codable, Equatable, Sendable {
    let bundleID: String
    let name: String
    let date: Date
}

/// "You usually open these together around 9 am."
struct WorkspaceSuggestion: Equatable, Sendable {
    let apps: [WorkspaceApp]
    let hour: Int
    let days: Int

    var name: String {
        switch hour {
        case 5..<12: return "Morning setup"
        case 12..<17: return "Afternoon setup"
        case 17..<23: return "Evening setup"
        default: return "Late setup"
        }
    }

    /// Identifies the suggestion so a dismissal sticks.
    var key: String { apps.map(\.bundleID).sorted().joined(separator: ",") }
}

/// Pure logic for Workspaces (Foundation only, so Build.command can check it alone).
enum WorkspacePolicy {
    /// Apps never suggested or quit (they are always around).
    static let alwaysRunning: Set<String> = [
        "com.apple.finder", "com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.dock",
        "com.apple.Spotlight", "com.apple.loginwindow", "com.apple.controlcenter", "com.apple.notificationcenterui",
    ]
    static let editors: [String] = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed",
        "com.sublimetext.4", "com.panic.Nova", "com.apple.dt.Xcode",
    ]

    /// The app folders open in: the first editor in the workspace, if any.
    static func folderOpener(for workspace: Workspace) -> String? {
        workspace.apps.map(\.bundleID).first { editors.contains($0) }
    }

    // MARK: Learning

    /// Launches within this gap belong to the same start-of-work session.
    static let sessionGap: TimeInterval = 10 * 60

    /// Suggests a workspace when the same three or more apps were opened
    /// together on three or more different days in the last two weeks, and
    /// no workspace (or dismissed suggestion) already covers them.
    static func suggestion(launches: [AppLaunch], existing: [Set<String>], dismissed: Set<String>,
                           now: Date, calendar: Calendar = .current, ownBundleID: String = "") -> WorkspaceSuggestion? {
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let recent = launches.filter { $0.date >= cutoff && !alwaysRunning.contains($0.bundleID) && $0.bundleID != ownBundleID }
            .sorted { $0.date < $1.date }
        guard recent.count >= 3 else { return nil }

        // Group launches into sessions.
        var sessions: [[AppLaunch]] = []
        for launch in recent {
            if let last = sessions.last?.last, launch.date.timeIntervalSince(last.date) <= sessionGap {
                sessions[sessions.count - 1].append(launch)
            } else {
                sessions.append([launch])
            }
        }
        let sets = sessions.map { Set($0.map(\.bundleID)) }
        var best: (core: Set<String>, days: Int, hours: [Int])?
        for candidate in sets where candidate.count >= 3 {
            var core = candidate
            var days = Set<String>()
            var hours: [Int] = []
            for (otherIndex, other) in sets.enumerated() {
                let shared = core.intersection(other)
                guard shared.count >= 3 else { continue }
                core = shared
                let first = sessions[otherIndex][0].date
                days.insert(TimeTrackingPolicy.dayKey(first, calendar: calendar))
                hours.append(calendar.component(.hour, from: first))
            }
            guard days.count >= 3, core.count >= 3 else { continue }
            if best == nil || days.count > best!.days || (days.count == best!.days && core.count > best!.core.count) {
                best = (core, days.count, hours)
            }
        }
        guard let best else { return nil }
        if existing.contains(where: { best.core.isSubset(of: $0) }) { return nil }
        let names = Dictionary(recent.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { _, latest in latest })
        // In the order they're usually opened.
        let order = recent.map(\.bundleID)
        let apps = best.core.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            .map { WorkspaceApp(bundleID: $0, name: names[$0] ?? $0) }
        let sortedHours = best.hours.sorted()
        let suggestion = WorkspaceSuggestion(apps: apps, hour: sortedHours[sortedHours.count / 2], days: best.days)
        return dismissed.contains(suggestion.key) ? nil : suggestion
    }

    /// Keeps two weeks of launches, at most `limit`.
    static func trimmed(_ launches: [AppLaunch], now: Date, limit: Int = 600) -> [AppLaunch] {
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        return Array(launches.filter { $0.date >= cutoff }.suffix(limit))
    }

    // MARK: Layout

    /// Frames for the first windows, in screen coordinates with the origin at
    /// the top left (as Accessibility uses), inside the visible area.
    static func frames(for layout: Workspace.Layout, visible: CGRect, count: Int) -> [CGRect] {
        let columns: Int
        switch layout {
        case .none, .restore: return []
        case .sideBySide: columns = 2
        case .thirds: columns = 3
        }
        let used = min(columns, count)
        guard used > 0, visible.width > 0, visible.height > 0 else { return [] }
        let width = (visible.width / CGFloat(columns)).rounded(.down)
        return (0..<used).map { index in
            CGRect(x: visible.minX + CGFloat(index) * width, y: visible.minY, width: width, height: visible.height)
        }
    }

    // MARK: Restoring saved windows

    /// Pairs saved windows with the app's current windows: same title first,
    /// then the rest in order.
    static func matchWindows(saved: [WorkspaceWindow], titles: [String]) -> [(saved: Int, window: Int)] {
        var pairs: [(saved: Int, window: Int)] = []
        var usedSaved = Set<Int>(), usedWindows = Set<Int>()
        for (index, window) in saved.enumerated() {
            guard let title = window.title, !title.isEmpty,
                  let match = titles.indices.first(where: { !usedWindows.contains($0) && titles[$0] == title }) else { continue }
            pairs.append((index, match)); usedSaved.insert(index); usedWindows.insert(match)
        }
        let restSaved = saved.indices.filter { !usedSaved.contains($0) }
        let restWindows = titles.indices.filter { !usedWindows.contains($0) }
        for (savedIndex, windowIndex) in zip(restSaved, restWindows) { pairs.append((savedIndex, windowIndex)) }
        return pairs.sorted { $0.saved < $1.saved }
    }

    /// A saved frame, moved onto a screen if its screen is gone (a monitor
    /// unplugged) and no bigger than that screen.
    static func fitted(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let first = screens.first else { return frame }
        func overlap(_ screen: CGRect) -> CGFloat {
            let shared = frame.intersection(screen)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        let target = screens.max { overlap($0) < overlap($1) } ?? first
        let visibleShare = overlap(target) / max(1, frame.width * frame.height)
        let size = CGSize(width: min(frame.width, target.width), height: min(frame.height, target.height))
        if visibleShare >= 0.5 && size == frame.size { return frame }
        // Keep it where it was as far as possible, inside the screen.
        let x = min(max(frame.minX, target.minX), target.maxX - size.width)
        let y = min(max(frame.minY, target.minY), target.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: Window setups

    /// What "Save current" keeps: the apps that have windows on screen, each
    /// with those windows. Apps without a visible window aren't part of it.
    static func windowsOnly(_ apps: [WorkspaceApp]) -> [WorkspaceApp] {
        apps.filter { !($0.windows ?? []).isEmpty }
    }

    /// A setup saved from the screen, as setups are kept now: just its
    /// windows, no web pages (opening them every time made duplicate tabs).
    /// Setups made by hand in Settings, without saved windows, are left alone.
    static func windowsOnlySetup(_ workspace: Workspace) -> Workspace {
        guard workspace.layout == .restore || workspace.apps.contains(where: { !($0.windows ?? []).isEmpty }) else { return workspace }
        var setup = workspace
        setup.apps = windowsOnly(workspace.apps)
        setup.urls = []
        setup.layout = .restore
        return setup
    }

    /// How many windows to open for an app that has fewer than the setup saved.
    static func windowsToOpen(saved: Int, open: Int) -> Int {
        max(0, min(saved - open, 4))
    }

    /// AppleScript that opens one new window in a browser, when there is one for it.
    static func newWindowScript(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return #"tell application id "com.apple.Safari" to make new document"#
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi":
            return "tell application id \"\(bundleID)\" to make new window"
        default:
            return nil
        }
    }

    // MARK: Done for the day

    /// The apps to quit: ones a workspace opened today that are still running.
    static func appsToQuit(launchedByWorkspaces: Set<String>, running: [String], ownBundleID: String) -> [String] {
        running.filter { launchedByWorkspaces.contains($0) && !alwaysRunning.contains($0) && $0 != ownBundleID }
    }

    /// Normalizes a typed web address ("github.com" → "https://github.com").
    static func normalizedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let host = url.host, host.contains(".") || host == "localhost" else { return nil }
        return url
    }
}
