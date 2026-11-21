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

    /// Why a panel shows no picture, by panel id.
    @Published private(set) var problems: [UUID: String] = [:]

    private final class Target {
        weak var layer: CALayer?
        var panel: GlancePanel
        var capture: GlanceWindowCapture?
        init(layer: CALayer, panel: GlancePanel) {
            self.layer = layer
            self.panel = panel
        }
    }

    private var targets: [UUID: Target] = [:]
    private var running = false

    /// A window you can put on a board.
    struct Choice: Identifiable, Hashable {
        let bundleID: String
        let appName: String
        let title: String
        var id: String { bundleID + "|" + title }
    }

    /// Called by the panel's view: where its picture goes.
    func register(_ panel: GlancePanel, layer: CALayer) {
        if let target = targets[panel.id] {
            let changed = target.panel.windowApp != panel.windowApp || target.panel.windowTitle != panel.windowTitle
                || target.layer !== layer
            target.panel = panel
            target.layer = layer
            if changed, running {
                target.capture?.stop()
                target.capture = nil
                Task { await start(panel.id) }
            }
            return
        }
        targets[panel.id] = Target(layer: layer, panel: panel)
        if running { Task { await start(panel.id) } }
    }

    /// The board opened: start capturing every registered window.
    func resume() {
        running = true
        let shown = Set(GlanceManager.shared.boardsOnScreen.flatMap(\.panels).filter { $0.isShown && $0.kind == .window }.map(\.id))
        for id in targets.keys where !shown.contains(id) { targets[id]?.capture?.stop(); targets[id] = nil }
        for id in targets.keys where targets[id]?.capture == nil { Task { await start(id) } }
    }

    /// The board closed: stop every capture (nothing is recorded while you work).
    func pauseAll() {
        running = false
        for target in targets.values {
            target.capture?.stop()
            target.capture = nil
        }
    }

    private func start(_ id: UUID) async {
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
                let choice = Choice(bundleID: app.bundleIdentifier, appName: app.applicationName, title: window.title ?? "")
                return seen.insert(choice.id).inserted ? choice : nil
            }
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
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
