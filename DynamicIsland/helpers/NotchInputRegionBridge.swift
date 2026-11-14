// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Attach at the visible surface's background, before shadow padding or offsets.
/// Native window input follows this shape rather than the larger hosting window.
struct NotchInputRegionBridge<HitShape: Shape>: NSViewRepresentable {
    let shape: HitShape
    let isExpanded: Bool
    let enabled: Bool
    let collapsedSize: CGSize?
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NotchInputRegionProbe { NotchInputRegionProbe() }

    func updateNSView(_ view: NotchInputRegionProbe, context: Context) {
        view.isExpanded = isExpanded
        view.regionEnabled = enabled
        view.collapsedSize = collapsedSize
        view.makePath = { rect in shape.path(in: rect).cgPath }
        view.onHover = onHover
        view.refreshRegion()
    }

    static func dismantleNSView(_ view: NotchInputRegionProbe, coordinator: ()) {
        view.detach()
    }
}

@MainActor
final class NotchInputRegionProbe: NSView {
    var isExpanded = false
    var regionEnabled = true
    var collapsedSize: CGSize?
    var makePath: (CGRect) -> CGPath = { CGPath(rect: $0, transform: nil) }
    var onHover: (Bool) -> Void = { _ in }
    private weak var registeredWindow: DynamicIslandWindow?
    private var lastCollapsedSize: CGSize?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let registeredWindow, registeredWindow !== window { registeredWindow.removeInputRegion(self) }
        registeredWindow = window as? DynamicIslandWindow
        registeredWindow?.installInputRegion(self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshRegion()
    }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        refreshRegion()
    }
    override func layout() {
        super.layout()
        refreshRegion()
    }

    func refreshRegion() {
        // During a close SwiftUI can publish the new state before reducing the
        // representable's expanded frame. Preserve the last genuinely closed
        // measurement, including media/timer/extension wings, for that interval.
        if !isExpanded, bounds.width > 0, bounds.height > 0,
           let expectedHeight = collapsedSize?.height ?? lastCollapsedSize?.height,
           bounds.height <= expectedHeight + 0.5 {
            lastCollapsedSize = bounds.size
        }
        registeredWindow?.refreshInputRegion()
    }
    func detach() {
        registeredWindow?.removeInputRegion(self)
        registeredWindow = nil
    }

    private var interactionRect: CGRect {
        let closedTarget: CGSize? = collapsedSize.map {
            // Width is content-driven (timer labels and extension wings). Use
            // its last real closed measurement, while current hover/HUD flags
            // immediately supply the correct height when closing.
            CGSize(width: lastCollapsedSize?.width ?? $0.width, height: $0.height)
        } ?? lastCollapsedSize
        return NotchInputRegionPolicy.interactionRect(in: bounds, isExpanded: isExpanded,
                                                     collapsedSize: closedTarget)
    }

    func contains(screenPoint: NSPoint) -> Bool {
        guard regionEnabled, let window else { return false }
        let localPoint = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let rect = interactionRect
        guard !rect.isEmpty, rect.contains(localPoint) else { return false }
        return makePath(rect).contains(localPoint)
    }

    func containsHoverActivation(screenPoint: NSPoint) -> Bool {
        if contains(screenPoint: screenPoint) { return true }
        guard regionEnabled, !isExpanded, let window else { return false }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let rect = interactionRect
        // Keep the existing screen-edge hover affordance without turning this
        // small activation margin into an area that captures another app's click.
        return rect.width > 0 && point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY - 4 && point.y <= rect.minY + 1
    }
}

/// Read-only monitors keep hover working while the panel passes outside clicks
/// through. They never consume, synthesize, or replay another app's event.
@MainActor
final class NotchWindowInputController {
    private weak var window: DynamicIslandWindow?
    private weak var probe: NotchInputRegionProbe?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var releaseTimer: Timer?
    private var capturedPress = false
    private var hovering = false
    private var hoverGeneration = 0

    init(window: DynamicIslandWindow) { self.window = window }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        releaseTimer?.invalidate()
    }

    func install(_ probe: NotchInputRegionProbe) {
        if self.probe !== probe {
            deliverHover(false)
        }
        self.probe = probe
        resume()
    }
    func remove(_ probe: NotchInputRegionProbe) {
        guard self.probe === probe else { return }
        suspend()
        self.probe = nil
    }

    func resume() {
        guard let window, window.isVisible, probe != nil else { refresh(); return }
        if localMonitor == nil {
            let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                                .leftMouseUp, .rightMouseUp, .otherMouseUp]
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.observe(event, local: true)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
                self?.observe(event, local: false)
            }
        }
        refresh()
    }

    func suspend() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        capturedPress = false
        window?.ignoresMouseEvents = true
        deliverHover(false)
    }

    func refresh() {
        guard let window else { return }
        if capturedPress && NSEvent.pressedMouseButtons == 0 { finishPress() }
        let visible = window.isVisible && window.alphaValue > 0.01
        let location = NSEvent.mouseLocation
        let inside = visible && probe?.contains(screenPoint: location) == true
        let ignoresMouseEvents = !(visible && (inside || capturedPress))
        if window.ignoresMouseEvents != ignoresMouseEvents {
            window.ignoresMouseEvents = ignoresMouseEvents
        }
        deliverHover(visible && probe?.containsHoverActivation(screenPoint: location) == true)
    }

    func contains(screenPoint: NSPoint) -> Bool {
        guard let window, window.isVisible, window.alphaValue > 0.01 else { return false }
        return probe?.contains(screenPoint: screenPoint) == true
    }

    private func observe(_ event: NSEvent, local: Bool) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if local, let window, event.window === window {
                let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
                if probe?.contains(screenPoint: screenPoint) == true {
                    capturedPress = true
                    startReleaseCheck()
                }
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            finishPress()
        default: break
        }
        refresh()
    }

    private func startReleaseCheck() {
        guard releaseTimer == nil else { return }
        // NSButton/drag tracking loops can consume mouseUp before sendEvent.
        // Poll only during a captured press, never continuously while idle.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons == 0 { self.finishPress(); self.refresh() }
            }
        }
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func finishPress() {
        capturedPress = false
        releaseTimer?.invalidate()
        releaseTimer = nil
    }

    private func deliverHover(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        hoverGeneration += 1
        let generation = hoverGeneration
        let callback = probe?.onHover
        // A region can change during SwiftUI layout. Defer SwiftUI state writes.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hoverGeneration == generation else { return }
            callback?(value)
        }
    }
}
