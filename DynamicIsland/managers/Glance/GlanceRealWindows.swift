// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import Defaults

/// Real windows on the board, instead of pictures of them (no screen
/// recording): web pages open as windows of your own browser (Chrome Beta,
/// Chrome, Edge, Brave, Vivaldi as borderless app windows; Safari as a
/// window), so they're signed in as you; app panels use the app's own window.
///
/// When Glance opens, each window moves into its panel's spot and comes
/// above the board; when it closes, browser windows wait just off screen
/// (loaded, for next time) and app windows go back where they were.
@MainActor
final class GlanceRealWindows: ObservableObject {
    static let shared = GlanceRealWindows()

    /// Why a panel's window isn't there, by panel id ("On another desktop").
    @Published private(set) var problems: [UUID: String] = [:]
    /// Panels whose window is being opened.
    @Published private(set) var opening: Set<UUID> = []
    /// Where each real window is on the board right now (Accessibility
    /// coordinates; its real size, which can be bigger than the panel when
    /// the app has a minimum). The board leaves a clear gap there.
    @Published private(set) var placedFrames: [UUID: CGRect] = [:]

    /// The browser window opened for each web panel, and the address it opened.
    private var browserWindows: [UUID: (window: AXUIElement, pid: pid_t, address: String, browser: String)] = [:]
    /// Windows on the board right now, and where app windows were before.
    private var placed: [(panelID: UUID, window: AXUIElement, pid: pid_t, original: CGRect?, isBrowser: Bool)] = []
    private var presentTask: Task<Void, Never>?

    // MARK: Settings

    /// The browser web pages open in (nil: NotchFlow's own built-in pages).
    static var browser: GlancePolicy.Browser? {
        let installed = Set(GlancePolicy.browsers.map(\.bundleID).filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
        return GlancePolicy.browser(setting: Defaults[.glanceBrowser], installed: installed)
    }

    /// Whether a panel shows a real window (rather than NotchFlow drawing it).
    static func usesRealWindow(_ panel: GlancePanel) -> Bool {
        switch panel.kind {
        case .web: return browser != nil && GlancePolicy.webURL(panel.address) != nil
        case .window: return !Defaults[.glanceLivePicture]
        default: return false
        }
    }

    /// Whether any real window is on the board now.
    var isPresenting: Bool { !placed.isEmpty }

    // MARK: Showing

    /// Moves every real-window panel's window into its spot on the boards
    /// being shown, then brings them above the board, in order.
    func present(_ layout: [(board: GlanceBoard, screen: NSScreen)]) {
        presentTask?.cancel()
        presentTask = Task { @MainActor in
            guard AXIsProcessTrusted() else {
                for (board, _) in layout {
                    for panel in board.panels where panel.isShown && Self.usesRealWindow(panel) {
                        problems[panel.id] = "Allow NotchFlow in System Settings › Privacy & Security › Accessibility to show real windows."
                    }
                }
                return
            }
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            for (board, screen) in layout {
                let area = GlanceLayout.boardArea(screen.frame.size)
                for panel in board.panels where panel.isShown && Self.usesRealWindow(panel) {
                    if Task.isCancelled { return }
                    let target = GlancePolicy.screenRect(for: panel.frame, area: area, gap: Double(GlanceLayout.gap),
                                                         display: screen.frame, mainDisplayHeight: Double(mainHeight))
                    await place(panel, at: target)
                }
            }
            raiseAll()
        }
    }

    /// Glance closed: browser windows wait off screen, app windows go back.
    func dismiss() {
        presentTask?.cancel()
        presentTask = nil
        let parking = GlancePolicy.parkingOrigin(displays: Self.displaysInAXCoordinates())
        for entry in placed {
            if entry.isBrowser {
                Self.setPosition(entry.window, CGPoint(x: parking.x, y: parking.y))
            } else if let original = entry.original {
                Self.setFrame(entry.window, original)
            }
        }
        placed = []
        placedFrames = [:]
    }

    /// Arranging the board: windows step aside so the tiles can be moved.
    func stepAside() {
        dismiss()
    }

    /// Whether a point (screen coordinates, bottom-left origin) is on a real window on the board.
    func contains(screenPoint point: NSPoint) -> Bool {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: mainHeight - point.y)
        return placed.contains { Self.frame(of: $0.window)?.contains(flipped) == true }
    }

    /// A web panel's page was removed or its address changed: its window closes.
    func forget(_ panelID: UUID) {
        if let entry = browserWindows.removeValue(forKey: panelID) { Self.close(entry.window) }
    }

    /// Closes the browser windows of panels that are gone.
    func keepOnly(_ panelIDs: Set<UUID>) {
        for id in browserWindows.keys where !panelIDs.contains(id) { forget(id) }
    }

    /// Opens the browser window for a new web panel now, off screen, so the first glance is instant.
    func prepare(_ panel: GlancePanel) {
        guard panel.kind == .web, Self.usesRealWindow(panel), browserWindows[panel.id] == nil else { return }
        Task { @MainActor in
            if let window = await openBrowserWindow(for: panel) {
                Self.setPosition(window.window, GlancePolicy.parkingOrigin(displays: Self.displaysInAXCoordinates()))
            }
        }
    }

    // MARK: Placing one

    private func place(_ panel: GlancePanel, at target: CGRect) async {
        problems[panel.id] = nil
        switch panel.kind {
        case .web:
            guard let window = await browserWindow(for: panel) else {
                problems[panel.id] = "\(Self.browser?.name ?? "The browser") didn't open the page."
                return
            }
            Self.setFrame(window.window, target)
            placed.append((panelID: panel.id, window: window.window, pid: window.pid, original: nil, isBrowser: true))
            placedFrames[panel.id] = Self.frame(of: window.window) ?? target
        case .window:
            guard let app = await runningApp(panel.windowApp) else {
                problems[panel.id] = "\(panel.title) isn't installed."
                return
            }
            guard let window = Self.window(of: app, title: panel.windowTitle, floating: panel.view == "floating") else {
                problems[panel.id] = "\(panel.title) has no window open."
                return
            }
            guard Self.isOnThisDesktop(window, pid: app.processIdentifier) else {
                problems[panel.id] = "\(panel.title)'s window is on another desktop. To have it everywhere: right-click its Dock icon › Options › All Desktops."
                return
            }
            let original = Self.frame(of: window)
            if Self.isMinimized(window) { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            Self.setFrame(window, target)
            placed.append((panelID: panel.id, window: window, pid: app.processIdentifier, original: original, isBrowser: false))
            // Its real frame: apps with a minimum size, or a fixed one (a mini player), stay bigger.
            if var actual = Self.frame(of: window) {
                if actual.width > target.width + 2 || actual.height > target.height + 2 {
                    // Centred on the panel instead of hanging off its corner.
                    actual.origin = CGPoint(x: target.midX - actual.width / 2, y: target.midY - actual.height / 2)
                    Self.setPosition(window, actual.origin)
                }
                placedFrames[panel.id] = actual
            } else {
                placedFrames[panel.id] = target
            }
        default:
            return
        }
    }

    /// Above the board, one by one: each window becomes its app's main window and
    /// the app comes forward with only that window (not all of its windows).
    private func raiseAll() {
        // The board leaves a clear gap where each window is, so it only has
        // to be above the other apps' windows there.
        for entry in placed {
            AXUIElementPerformAction(entry.window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(entry.window, kAXMainAttribute as CFString, kCFBooleanTrue)
            let app = AXUIElementCreateApplication(entry.pid)
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: entry.pid)?.activate()
        }
    }

    // MARK: Browser windows

    /// The panel's browser window: the one opened before when it's still
    /// there, on this desktop and on the same page; else a new one.
    private func browserWindow(for panel: GlancePanel) async -> (window: AXUIElement, pid: pid_t)? {
        guard let browser = Self.browser else { return nil }
        if let existing = browserWindows[panel.id] {
            if existing.browser == browser.bundleID, existing.address == panel.address, Self.isAlive(existing.window),
               Self.isOnThisDesktop(existing.window, pid: existing.pid) {
                return (existing.window, existing.pid)
            }
            // Another desktop, another page or another browser: a fresh window here.
            Self.close(existing.window)
            browserWindows[panel.id] = nil
        }
        return await openBrowserWindow(for: panel)
    }

    private func openBrowserWindow(for panel: GlancePanel) async -> (window: AXUIElement, pid: pid_t)? {
        guard let browser = Self.browser, let url = GlancePolicy.webURL(panel.address),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else { return nil }
        opening.insert(panel.id)
        defer { opening.remove(panel.id) }

        let before = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first
        let known = before.map { Self.windows(of: $0) } ?? []
        if browser.isChromium {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.createsNewApplicationInstance = before == nil ? false : true
            configuration.arguments = GlancePolicy.appWindowArguments(url: url)
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            if before == nil {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            try? await AppleScriptHelper.executeVoid(GlancePolicy.safariWindowScript(url: url))
        }
        // The new window appears in a moment.
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first else { continue }
            if let window = Self.windows(of: app).first(where: { candidate in !known.contains { CFEqual($0, candidate) } }) {
                browserWindows[panel.id] = (window: window, pid: app.processIdentifier, address: panel.address, browser: browser.bundleID)
                return (window, app.processIdentifier)
            }
        }
        return nil
    }

    // MARK: App windows

    private func runningApp(_ bundleID: String) async -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { return app }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, !Self.windows(of: app).isEmpty {
                return app
            }
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// The window under a point on screen (bottom-left origin), not NotchFlow's:
    /// its app, title, and whether it floats (a mini player, a palette).
    static func windowAt(screenPoint point: NSPoint) -> (bundleID: String, appName: String, title: String, floating: Bool)? {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: mainHeight - point.y)
        let own = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != own,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer >= 0, layer < 25,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(flipped),
                  rect.width > 60, rect.height > 40,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited,
                  let bundleID = app.bundleIdentifier else { continue }
            // Its Accessibility window, by frame, for the title.
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 1)
            let windows = (value(element, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            let match = windows.first { window in
                guard let frame = frame(of: window) else { return false }
                return abs(frame.minX - rect.minX) < 3 && abs(frame.minY - rect.minY) < 3 && abs(frame.width - rect.width) < 3
            }
            let subrole = match.flatMap { value($0, kAXSubroleAttribute) as? String } ?? ""
            return (bundleID, app.localizedName ?? bundleID, match.flatMap { title(of: $0) } ?? "",
                    subrole == (kAXFloatingWindowSubrole as String) || layer > 0)
        }
        return nil
    }

    /// Open windows of running apps, by Accessibility (no screen recording), for picking one.
    static func appWindows() -> [(bundleID: String, appName: String, title: String)] {
        guard AXIsProcessTrusted() else { return [] }
        let own = Bundle.main.bundleIdentifier
        var result: [(bundleID: String, appName: String, title: String)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.bundleIdentifier != own {
            guard let bundleID = app.bundleIdentifier else { continue }
            for window in windows(of: app) {
                result.append((bundleID: bundleID, appName: app.localizedName ?? bundleID, title: title(of: window) ?? ""))
            }
        }
        return result
    }

    // MARK: Accessibility helpers

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    /// An app's windows you'd put on a board: ordinary ones and floating
    /// ones like a mini player (not sheets, menus or tiny palettes).
    static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1)
        guard let list = value(element, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return list.filter { window in
            let subrole = value(window, kAXSubroleAttribute) as? String
            if subrole == (kAXStandardWindowSubrole as String) { return true }
            guard subrole == (kAXFloatingWindowSubrole as String), let frame = frame(of: window) else { return false }
            return frame.width >= 120 && frame.height >= 60
        }
    }

    private static func isFloating(_ window: AXUIElement) -> Bool {
        (value(window, kAXSubroleAttribute) as? String) == (kAXFloatingWindowSubrole as String)
    }

    private static func window(of app: NSRunningApplication, title wanted: String, floating: Bool = false) -> AXUIElement? {
        let list = windows(of: app)
        if !wanted.isEmpty, let match = list.first(where: { title(of: $0) == wanted && (!floating || isFloating($0)) }) { return match }
        if floating, let match = list.first(where: isFloating) { return match }
        if !wanted.isEmpty, let match = list.first(where: { title(of: $0) == wanted }) { return match }
        if let main = value(AXUIElementCreateApplication(app.processIdentifier), kAXMainWindowAttribute),
           CFGetTypeID(main) == AXUIElementGetTypeID() {
            return (main as! AXUIElement)
        }
        return list.first
    }

    private static func title(of window: AXUIElement) -> String? { value(window, kAXTitleAttribute) as? String }

    private static func isAlive(_ window: AXUIElement) -> Bool { value(window, kAXRoleAttribute) != nil }

    private static func isMinimized(_ window: AXUIElement) -> Bool { (value(window, kAXMinimizedAttribute) as? Bool) == true }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = value(window, kAXPositionAttribute), let size = value(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var origin = point
        if let value = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    /// Moves, resizes, then moves again (some apps limit size by position).
    private static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size
        setPosition(window, frame.origin)
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
        setPosition(window, frame.origin)
    }

    private static func close(_ window: AXUIElement) {
        if let button = value(window, kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    /// Whether a window is on the desktop you're looking at (the window
    /// server's on-screen list holds only this desktop's windows).
    private static func isOnThisDesktop(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard let frame = frame(of: window),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(rect.minX - frame.minX) < 3 && abs(rect.minY - frame.minY) < 3
                && abs(rect.width - frame.width) < 3 && abs(rect.height - frame.height) < 3
        }
    }

    private static func displaysInAXCoordinates() -> [CGRect] {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        }
    }
}
