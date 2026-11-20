// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import Combine
import Defaults
import ScreenCaptureKit
import SwiftUI

extension Defaults.Keys {
    /// A parking spot for windows in the Flow tab.
    static let enableWindowStash = Key<Bool>("enableWindowStash", default: true)
    /// Drag a window by its title bar into the notch to stash it.
    static let windowStashByDragging = Key<Bool>("windowStashByDragging", default: true)
}

/// A window parked in the Flow tab: minimized out of the way, with where it
/// was, so it comes back exactly there.
struct StashedWindow: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let title: String
    /// Where it was before it was stashed (Accessibility coordinates).
    let frame: CGRect
    let preview: NSImage?
    let stashedAt = Date()

    var icon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}

/// Stashes windows: drag one into the notch, or "Stash all" to park every
/// window except the front app's. Needs Accessibility; previews need Screen
/// Recording (without it, the app icon stands in).
@MainActor
final class WindowStash: ObservableObject {
    static let shared = WindowStash()

    @Published private(set) var items: [StashedWindow] = []
    @Published private(set) var lastMessage: String?

    private var monitors: [Any] = []
    private var settings: AnyCancellable?
    private var terminations: AnyCancellable?
    /// The drag in progress: where the button went down, and the window
    /// under it once the drag is noticed.
    private var dragDown: CGPoint?
    private var dragWindow: (element: AXUIElement, pid: pid_t, frameBefore: CGRect)?
    private var dragInZone = false
    private static let limit = 24

    private init() {}

    func start() {
        guard settings == nil else { return }
        settings = Publishers.CombineLatest(Defaults.publisher(.enableWindowStash), Defaults.publisher(.windowStashByDragging))
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, dragging in self?.configure(watchDrags: enabled.newValue && dragging.newValue) }
        terminations = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.items.removeAll { $0.pid == app.processIdentifier }
            }
    }

    private func configure(watchDrags: Bool) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard watchDrags else { return }
        // Global monitors only see other apps' events, and only mouse buttons: cheap.
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) { monitors.append(down) }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }) { monitors.append(drag) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }) { monitors.append(up) }
    }

    // MARK: Dragging into the notch

    private func mouseDown() {
        dragDown = Self.pointer()
        dragWindow = nil
        dragInZone = false
    }

    private func mouseDragged() {
        guard let down = dragDown, AXIsProcessTrusted() else { return }
        let now = Self.pointer()
        if dragWindow == nil {
            // The first drag event: the window being dragged is under the pointer.
            guard let (window, pid) = Self.window(at: now), let frame = AXWindowTools.frame(of: window) else {
                dragDown = nil // Not a window: stop looking until the next click.
                return
            }
            dragWindow = (window, pid, WindowStashPolicy.frameBeforeDrag(noticed: frame, pointerAtDown: down, pointerAtNotice: now))
        }
        let inZone = Self.zones().contains { $0.contains(now) }
        if inZone && !dragInZone {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        dragInZone = inZone
    }

    private func mouseUp() {
        defer { dragDown = nil; dragWindow = nil; dragInZone = false }
        guard let down = dragDown, let drag = dragWindow, Defaults[.enableWindowStash] else { return }
        let up = Self.pointer()
        guard WindowStashPolicy.isDropIntoNotch(down: down, up: up, frameAtStart: drag.frameBefore,
                                                frameAtEnd: AXWindowTools.frame(of: drag.element), zones: Self.zones()) else { return }
        Task { await stash(drag.element, pid: drag.pid, returningTo: drag.frameBefore) }
    }

    // MARK: Stashing

    /// Parks every window except the front app's.
    func stashAllOthers() async {
        guard AXIsProcessTrusted() else {
            lastMessage = "Allow NotchFlow in System Settings › Privacy & Security › Accessibility to stash windows."
            return
        }
        let front = Self.frontApp()?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        var count = 0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden
            && app.processIdentifier != front && app.processIdentifier != own {
            for window in AXWindowTools.standardWindows(of: app.processIdentifier) {
                guard items.count < Self.limit, let frame = AXWindowTools.frame(of: window) else { continue }
                if await stash(window, pid: app.processIdentifier, returningTo: frame, quietly: true) { count += 1 }
            }
        }
        lastMessage = count == 0 ? "No other windows to stash." : "Stashed \(count) window\(count == 1 ? "" : "s")."
    }

    @discardableResult
    private func stash(_ window: AXUIElement, pid: pid_t, returningTo frame: CGRect, quietly: Bool = false) async -> Bool {
        guard items.count < Self.limit else {
            lastMessage = "The stash is full (\(Self.limit) windows). Bring some back first."
            return false
        }
        guard !items.contains(where: { CFEqual($0.element, window) }) else { return false }
        let app = NSRunningApplication(processIdentifier: pid)
        let title = AXWindowTools.title(of: window) ?? ""
        let preview = await Self.preview(pid: pid, title: title, frame: AXWindowTools.frame(of: window) ?? frame)
        // Back where it was, then out of the way: it returns to that spot.
        AXWindowTools.move(window, to: frame)
        guard AXWindowTools.setMinimized(window, true) else {
            if !quietly { lastMessage = "\(app?.localizedName ?? "That app") didn't let its window be stashed." }
            return false
        }
        withAnimation(.smooth(duration: 0.25)) {
            items.insert(StashedWindow(element: window, pid: pid, appName: app?.localizedName ?? "App",
                                       bundleID: app?.bundleIdentifier, title: title, frame: frame, preview: preview), at: 0)
        }
        if !quietly { lastMessage = nil }
        return true
    }

    /// Brings a window back exactly where it was, in front.
    func restore(_ item: StashedWindow) {
        withAnimation(.smooth(duration: 0.25)) { items.removeAll { $0.id == item.id } }
        guard AXWindowTools.isAlive(item.element) else {
            lastMessage = "\(item.appName) closed that window."
            return
        }
        AXWindowTools.setMinimized(item.element, false)
        AXWindowTools.move(item.element, to: item.frame)
        AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: item.pid)?.activate()
    }

    func restoreAll() {
        for item in items.reversed() { restore(item) }
    }

    /// Forgets a window without bringing it back (it stays minimized in the Dock).
    func forget(_ item: StashedWindow) {
        withAnimation(.smooth(duration: 0.25)) { items.removeAll { $0.id == item.id } }
    }

    /// Closes a stashed window, as its close button would.
    func close(_ item: StashedWindow) {
        forget(item)
        AXWindowTools.close(item.element)
    }

    /// Drops windows that were closed, or brought back from the Dock.
    func refresh() {
        items.removeAll { !AXWindowTools.isAlive($0.element) || AXWindowTools.isMinimized($0.element) == false }
    }

    // MARK: Helpers

    private static func pointer() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: mouse.x, y: top - mouse.y)
    }

    /// Every screen's drop zone, in Accessibility coordinates.
    private static func zones() -> [CGRect] {
        guard let top = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            let frame = screen.frame
            let ax = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
            var notchMinX: CGFloat?, notchMaxX: CGFloat?
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                // These may be relative to the screen; make them global.
                let offset = left.minX < frame.minX - 1 ? frame.minX : 0
                notchMinX = left.maxX + offset
                notchMaxX = right.minX + offset
            }
            return WindowStashPolicy.zone(screen: ax, notchMinX: notchMinX, notchMaxX: notchMaxX)
        }
    }

    /// The standard window under a point, and its app.
    private static func window(at point: CGPoint) -> (AXUIElement, pid_t)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
        var current: AXUIElement? = hit
        for _ in 0..<12 {
            guard let element = current else { break }
            if AXWindowTools.role(of: element) == kAXWindowRole as String {
                return AXWindowTools.isStandard(element) ? (element, pid) : nil
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        return nil
    }

    private static func frontApp() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// A small picture of the window, when Screen Recording is allowed.
    private static func preview(pid: pid_t, title: String, frame: CGRect) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
        func distance(_ window: SCWindow) -> CGFloat {
            abs(window.frame.minX - frame.minX) + abs(window.frame.minY - frame.minY)
                + abs(window.frame.width - frame.width) + abs(window.frame.height - frame.height)
        }
        guard let window = candidates.filter({ title.isEmpty || $0.title == title }).min(by: { distance($0) < distance($1) })
                ?? candidates.min(by: { distance($0) < distance($1) }) else { return nil }
        let configuration = SCStreamConfiguration()
        let size = WindowStashPolicy.previewSize(for: window.frame.size, fitting: CGSize(width: 320, height: 200))
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                      configuration: configuration) else { return nil }
        return NSImage(cgImage: image, size: size)
    }
}

/// Small Accessibility helpers for one window.
enum AXWindowTools {
    static func role(of element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }

    static func isStandard(_ window: AXUIElement) -> Bool {
        string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
    }

    static func title(of window: AXUIElement) -> String? { string(window, kAXTitleAttribute) }

    static func standardWindows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { isStandard($0) && isMinimized($0) != true }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func move(_ window: AXUIElement, to frame: CGRect) {
        var origin = frame.origin, size = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    static func isMinimized(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    @discardableResult
    static func setMinimized(_ window: AXUIElement, _ minimized: Bool) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                     (minimized ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef) == .success
    }

    /// Whether the window still exists.
    static func isAlive(_ window: AXUIElement) -> Bool { role(of: window) != nil }

    static func close(_ window: AXUIElement) {
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
