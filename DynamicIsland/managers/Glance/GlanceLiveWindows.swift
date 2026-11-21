// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import CoreMedia
import ScreenCaptureKit

/// Live views of other apps' windows on Glance boards (ScreenCaptureKit,
/// with Screen Recording allowed), captured only while the board is on
/// screen, at about 12 frames a second.
@MainActor
final class GlanceLiveWindows: ObservableObject {
    static let shared = GlanceLiveWindows()

    /// Why a panel shows no picture, by instance (see GlanceManager.instanceKey).
    @Published private(set) var problems: [String: String] = [:]

    private final class Target {
        weak var layer: CALayer?
        var panel: GlancePanel
        var capture: GlanceWindowCapture?
        init(layer: CALayer, panel: GlancePanel) {
            self.layer = layer
            self.panel = panel
        }
    }

    private var targets: [String: Target] = [:]
    private var running = false

    /// A window you can put on a board.
    struct Choice: Identifiable, Hashable {
        let bundleID: String
        let appName: String
        let title: String
        /// The window right now (for its thumbnail).
        var windowID: UInt32 = 0
        var id: String { bundleID + "|" + title + "|\(windowID)" }
    }

    /// Called by the panel's view: where its picture goes.
    func register(_ panel: GlancePanel, instance: String, layer: CALayer) {
        if let target = targets[instance] {
            let changed = target.panel.windowApp != panel.windowApp || target.panel.windowTitle != panel.windowTitle
                || target.layer !== layer
            target.panel = panel
            target.layer = layer
            if changed, running {
                target.capture?.stop()
                target.capture = nil
                Task { await start(instance) }
            }
            return
        }
        targets[instance] = Target(layer: layer, panel: panel)
        if running { Task { await start(instance) } }
    }

    /// The board opened: start capturing every registered window.
    func resume() {
        running = true
        let shown = Set(GlanceManager.shared.boardsOnScreen.flatMap(\.panels).filter { $0.isShown && $0.kind == .window }.map(\.id))
        // Panels taken off a board, and views that are gone (a display not showing a board this time).
        for (key, target) in targets where !shown.contains(target.panel.id) || target.layer == nil {
            target.capture?.stop()
            targets[key] = nil
        }
        for key in targets.keys where targets[key]?.capture == nil { Task { await start(key) } }
    }

    /// The board closed: stop every capture (nothing is recorded while you work).
    func pauseAll() {
        running = false
        for target in targets.values {
            target.capture?.stop()
            target.capture = nil
        }
    }

    private func start(_ id: String) async {
        guard running, let target = targets[id], target.capture == nil, let layer = target.layer else { return }
        let panel = target.panel
        guard !panel.windowApp.isEmpty else {
            problems[id] = "Pick a window for this panel in Settings › Glance."
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            problems[id] = "Allow NotchFlow in System Settings › Privacy & Security › Screen Recording to show live windows."
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let windows = content.windows.filter { $0.windowLayer == 0 }
            let candidates = windows.map {
                GlancePolicy.WindowCandidate(bundleID: $0.owningApplication?.bundleIdentifier ?? "", title: $0.title ?? "",
                                             area: Double($0.frame.width * $0.frame.height))
            }
            guard let index = GlancePolicy.pickWindow(candidates, app: panel.windowApp, title: panel.windowTitle) else {
                problems[id] = "\(panel.title) isn't open."
                return
            }
            let window = windows[index]
            let configuration = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let fit = min(1, 1600 / max(1, window.frame.width * scale))
            configuration.width = max(64, Int(window.frame.width * scale * fit))
            configuration.height = max(64, Int(window.frame.height * scale * fit))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 12)
            configuration.showsCursor = false
            configuration.queueDepth = 3
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            let capture = GlanceWindowCapture(layer: layer)
            try await capture.start(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
            guard running, targets[id] === target else {
                capture.stop()
                return
            }
            target.capture = capture
            problems[id] = nil
        } catch {
            problems[id] = "The window couldn't be shown: \(error.localizedDescription)"
        }
    }

    /// Windows open now, for picking one in Settings (not NotchFlow's own).
    func choices() async -> [Choice] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return content.windows
            .filter { $0.windowLayer == 0 && $0.frame.width * $0.frame.height >= 10_000 }
            .compactMap { window -> Choice? in
                guard let app = window.owningApplication, app.bundleIdentifier != own, !app.bundleIdentifier.isEmpty else { return nil }
                let choice = Choice(bundleID: app.bundleIdentifier, appName: app.applicationName, title: window.title ?? "",
                                    windowID: window.windowID)
                return seen.insert(choice.id).inserted ? choice : nil
            }
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    /// A small picture of a window, for picking it.
    func thumbnail(for choice: Choice) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == choice.windowID }) else { return nil }
        let configuration = SCStreamConfiguration()
        let scale = min(1, 360 / max(1, window.frame.width))
        configuration.width = max(32, Int(window.frame.width * scale))
        configuration.height = max(32, Int(window.frame.height * scale))
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                     configuration: configuration) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    // MARK: Using a window in its panel

    /// Windows moved into their panels, and where they were.
    private var moved: [(window: AXUIElement, frame: CGRect)] = []

    /// Moves the real window onto its panel (Accessibility coordinates) and
    /// brings it forward, so you can use it there. False when it can't be found.
    func moveIntoPanel(_ panel: GlancePanel, frame: CGRect) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: panel.windowApp).first,
              let window = Self.axWindow(of: app, title: panel.windowTitle),
              let original = Self.frame(of: window) else { return false }
        if !moved.contains(where: { CFEqual($0.window, window) }) { moved.append((window, original)) }
        Self.set(window, frame: frame)
        app.activate()
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    /// Glance closed: the windows go back where they were.
    func restoreMoved() {
        for entry in moved { Self.set(entry.window, frame: entry.frame) }
        moved = []
    }

    private static func axWindow(of app: NSRunningApplication, title: String) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement], !windows.isEmpty {
            if !title.isEmpty, let match = windows.first(where: { window in
                var text: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &text)
                return (text as? String) == title
            }) { return match }
        }
        var main: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXMainWindowAttribute as CFString, &main) == .success, let main,
           CFGetTypeID(main) == AXUIElementGetTypeID() {
            return (main as! AXUIElement)
        }
        return (value as? [AXUIElement])?.first
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func set(_ window: AXUIElement, frame: CGRect) {
        var origin = frame.origin, size = frame.size
        if let value = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
        if let value = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    /// Clicking the panel: that window comes to the front.
    func bringForward(_ panel: GlancePanel) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: panel.windowApp).first else { return }
        app.activate()
        guard AXIsProcessTrusted(), !panel.windowTitle.isEmpty else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if (title as? String) == panel.windowTitle {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }
}

/// One window's capture, drawn straight into a layer.
final class GlanceWindowCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private weak var layer: CALayer?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "notchflow.glance.capture", qos: .userInteractive)

    init(layer: CALayer) {
        self.layer = layer
    }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.layer?.contents = surface
        }
    }
}
