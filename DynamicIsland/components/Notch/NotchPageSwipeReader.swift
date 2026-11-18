// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import SwiftUI

/// Reads three-finger "swipe between pages" gestures over the view it backs
/// and reports a page step (+1 next, -1 previous).
///
/// Only the page-swipe event is used: two-finger scrolling stays with the
/// notch, where it switches tabs. macOS sends page swipes when System
/// Settings > Trackpad > More Gestures > Swipe between pages uses three fingers.
/// A local event monitor is used because SwiftUI views above an
/// NSViewRepresentable keep it from receiving events itself.
struct NotchPageSwipeReader: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onStep: onStep) }

    @MainActor
    final class Coordinator: NSObject {
        var onStep: (Int) -> Void
        private var monitor: Any?
        private var lastTimestamp: TimeInterval = 0

        init(onStep: @escaping (Int) -> Void) { self.onStep = onStep }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self, weak view] event in
                guard let self, let view, self.isPointer(over: view) else { return event }
                return self.handle(event) ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Returns true when the event was used for paging.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.timestamp != lastTimestamp else { return false }
            lastTimestamp = event.timestamp
            guard let step = ClipboardPageSwipe.step(forSwipeDeltaX: Double(event.deltaX)) else { return false }
            onStep(step)
            return true
        }

        private func isPointer(over view: NSView) -> Bool {
            guard let window = view.window, !view.isHiddenOrHasHiddenAncestor else { return false }
            let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            return view.bounds.contains(point)
        }
    }
}
