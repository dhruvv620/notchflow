// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import Defaults

/// Playing a song picked in the notch on YouTube Music without opening a tab
/// or bringing anything forward:
///
/// - in the YouTube Music desktop app when it's installed (its local API
///   server: the song goes next in the queue and plays), started hidden if needed;
/// - else in one YouTube Music window of your browser (signed in as you),
///   kept just off screen and reused for every song, and closed after 15
///   minutes without playing to free its memory.
@MainActor
final class YouTubeMusicPlayers {
    static let shared = YouTubeMusicPlayers()

    enum Outcome: Equatable {
        case app
        case browser(String)
        /// macOS didn't let NotchFlow control that browser (Automation).
        case needsPermission(String)
        case failed
    }

    private let appBundleID = YouTubeMusicConfiguration.default.bundleIdentifier
    private lazy var httpClient = YouTubeMusicHTTPClient(baseURL: YouTubeMusicConfiguration.default.baseURL)
    private lazy var auth = YouTubeMusicAuthManager(httpClient: httpClient)
    /// The browser window songs play in (AppleScript window id).
    private var browserWindow: (bundleID: String, id: String, isChromium: Bool)?
    private var lastPlayed = Date.distantPast
    private var idleCheck: Timer?

    /// Whether the YouTube Music desktop app is installed.
    var hasDesktopApp: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) != nil }

    func play(videoID: String) async -> Outcome {
        if hasDesktopApp, await playInApp(videoID) { return .app }
        guard let url = MusicSearchPolicy.youtubeMusicWatchURL(videoID: videoID) else { return .failed }
        return await load(url, reveal: false)
    }

    /// The song couldn't be matched: YouTube Music's search for it, in the
    /// same player window, brought forward so you can pick.
    func showSearch(_ url: URL) async -> Outcome {
        await load(url, reveal: true)
    }

    // MARK: The desktop app

    private struct QueueBody: Codable, Sendable {
        let videoId: String
        let insertPosition: String
    }

    private func playInApp(_ videoID: String) async -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else { return false }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        // Its API server (the "API Server" plugin) answers a moment after it starts.
        for attempt in 0..<16 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
            guard let token = try? await auth.authenticate() else { continue }
            do {
                _ = try await httpClient.sendCommand(endpoint: "/queue", method: "POST",
                                                     body: QueueBody(videoId: videoID, insertPosition: "INSERT_AFTER_CURRENT_VIDEO"),
                                                     token: token)
                _ = try? await httpClient.sendCommand(endpoint: "/next", method: "POST", token: token)
                _ = try? await httpClient.sendCommand(endpoint: "/play", method: "POST", token: token)
                return true
            } catch {
                await auth.invalidateToken()
                return false
            }
        }
        return false
    }

    // MARK: One browser window

    /// The browser: the one Glance uses, else the first installed (Chrome Beta first, Safari last).
    private var browser: GlancePolicy.Browser? {
        if let chosen = GlanceRealWindows.browser { return chosen }
        let installed = Set(GlancePolicy.browsers.map(\.bundleID).filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
        return GlancePolicy.browser(setting: "auto", installed: installed)
    }

    /// Loads a YouTube Music page in the player window (the same one as
    /// before, one already open in that browser, else a new one off screen).
    private func load(_ url: URL, reveal: Bool) async -> Outcome {
        guard let browser else { return .failed }
        lastPlayed = Date()
        scheduleIdleCheck()
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first != nil

        func navigate(_ windowID: String) async -> Bool {
            let script = MusicSearchPolicy.youtubeMusicPlayScript(bundleID: browser.bundleID, isChromium: browser.isChromium,
                                                                  windowID: windowID, url: url)
            return (try? await AppleScriptHelper.executeVoid(script)) != nil
        }

        if running, let window = browserWindow, window.bundleID == browser.bundleID, await navigate(window.id) {
            if reveal { self.reveal(browser) }
            return .browser(browser.name)
        }
        if running {
            switch await playerWindow(browser) {
            case .found(let id):
                browserWindow = (browser.bundleID, id, browser.isChromium)
                if await navigate(id) {
                    if reveal { self.reveal(browser) }
                    return .browser(browser.name)
                }
            case .denied:
                return .needsPermission(browser.name)
            case .none:
                break
            }
        }
        guard await openPlayerWindow(browser, url, park: !reveal) else {
            // Couldn't tell: ask whether the browser can be controlled at all.
            if case .denied = await playerWindow(browser) { return .needsPermission(browser.name) }
            return .failed
        }
        if reveal { self.reveal(browser) }
        return .browser(browser.name)
    }

    private enum Lookup { case found(String), none, denied }

    /// The browser's YouTube Music window, if there is one; `.denied` when
    /// macOS doesn't let NotchFlow ask the browser (Automation not allowed).
    private func playerWindow(_ browser: GlancePolicy.Browser) async -> Lookup {
        let script = MusicSearchPolicy.youtubeMusicPlayerWindowScript(bundleID: browser.bundleID, isChromium: browser.isChromium)
        do {
            let found = try await AppleScriptHelper.execute(script)?.stringValue ?? ""
            return found.isEmpty ? .none : .found(found)
        } catch {
            return .denied
        }
    }

    /// Brings the player window forward, in the middle of the screen (to pick a song).
    private func reveal(_ browser: GlancePolicy.Browser) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first,
              let screen = NSScreen.main else { return }
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let size = CGSize(width: min(1100, screen.visibleFrame.width * 0.7), height: min(760, screen.visibleFrame.height * 0.8))
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: mainHeight - screen.visibleFrame.midY - size.height / 2,
                           width: size.width, height: size.height)
        for window in GlanceRealWindows.windows(of: app) where GlanceRealWindows.isParked(window) {
            GlanceRealWindows.move(window, to: frame)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        app.activate()
    }

    private func openPlayerWindow(_ browser: GlancePolicy.Browser, _ url: URL, park: Bool) async -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else { return false }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first
        let known = running.map { GlanceRealWindows.windows(of: $0) } ?? []
        if browser.isChromium {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.createsNewApplicationInstance = running != nil
            configuration.arguments = GlancePolicy.appWindowArguments(url: url)
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            if running == nil {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            guard (try? await AppleScriptHelper.executeVoid(GlancePolicy.safariWindowScript(url: url))) != nil else { return false }
        }
        // Its new window waits just off screen.
        var appeared = false
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first else { continue }
            if let window = GlanceRealWindows.windows(of: app).first(where: { candidate in !known.contains { CFEqual($0, candidate) } }) {
                if park { GlanceRealWindows.park(window) }
                appeared = true
                break
            }
        }
        // Its id, so the next songs play in it.
        if case .found(let id) = await playerWindow(browser) {
            browserWindow = (browser.bundleID, id, browser.isChromium)
            return true
        }
        return appeared
    }

    /// After 15 minutes without playing, the browser player window closes (its page uses memory).
    private func scheduleIdleCheck() {
        guard idleCheck == nil else { return }
        idleCheck = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in YouTubeMusicPlayers.shared.closeIfIdle() }
        }
    }

    private func closeIfIdle() {
        guard let window = browserWindow else {
            idleCheck?.invalidate()
            idleCheck = nil
            return
        }
        guard Date().timeIntervalSince(lastPlayed) > 15 * 60, !MusicManager.shared.isPlaying else { return }
        browserWindow = nil
        idleCheck?.invalidate()
        idleCheck = nil
        Task { try? await AppleScriptHelper.executeVoid(MusicSearchPolicy.youtubeMusicCloseScript(bundleID: window.bundleID, windowID: window.id)) }
    }
}
