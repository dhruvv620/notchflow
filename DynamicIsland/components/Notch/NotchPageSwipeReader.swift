// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Reads horizontal trackpad swipes over the view it backs and reports one
/// page step (+1 next, -1 previous) per gesture: a two-finger sideways scroll,
/// a three-finger page swipe (when macOS is set to swipe between pages with
/// three fingers), or a horizontal mouse-wheel click.
///
/// A local event monitor is used because SwiftUI views above an
/// NSViewRepresentable keep it from receiving scrollWheel/swipe itself (the
/// same approach as the timer ruler).
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
        private var accumulator = PageSwipeAccumulator()
        private var lastTimestamp: TimeInterval = 0

        init(onStep: @escaping (Int) -> Void) { self.onStep = onStep }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self, weak view] event in
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

            if event.type == .swipe {
                guard let step = PageSwipeAccumulator.step(forSwipeDeltaX: Double(event.deltaX)) else { return false }
                onStep(step)
                return true
            }

            let deltaX = Double(event.scrollingDeltaX)
            let deltaY = Double(event.scrollingDeltaY)
            // Only sideways movement pages; vertical scrolling is left alone.
            guard abs(deltaX) > abs(deltaY) else { return false }

            if event.phase.isEmpty && event.momentumPhase.isEmpty {
                // A mouse wheel: one step per click.
                guard let step = PageSwipeAccumulator.step(forWheelDeltaX: deltaX) else { return false }
                onStep(step)
                return true
            }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulator.begin()
            }
            // Momentum after the fingers lift belongs to the swipe already counted.
            guard event.momentumPhase.isEmpty else { return true }
            let units = event.hasPreciseScrollingDeltas ? deltaX : deltaX * 10
            if let step = accumulator.add(units) { onStep(step) }
            return true
        }

        private func isPointer(over view: NSView) -> Bool {
            guard let window = view.window, !view.isHiddenOrHasHiddenAncestor else { return false }
            let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            return view.bounds.contains(point)
        }
    }
}
