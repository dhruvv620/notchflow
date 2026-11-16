// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Cursor rectangles follow the card's native bounds and are removed with its view.
/// The background never participates in hit testing, so the SwiftUI button owns clicks.
struct PointingHandCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }

    func updateNSView(_ nsView: CursorView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    static func dismantleNSView(_ nsView: CursorView, coordinator: ()) {
        nsView.discardCursorRects()
    }

    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return }
            addCursorRect(visibleRect, cursor: .pointingHand)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            window?.invalidateCursorRects(for: self)
        }
    }
}
