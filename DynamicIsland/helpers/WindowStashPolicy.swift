// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Pure logic for the window stash (Foundation only, so Build.command can
/// check it alone). Rectangles are in Accessibility coordinates: the top
/// left of the main display is 0,0 and y grows downward.
enum WindowStashPolicy {
    /// How far below the top of the screen the drop zone reaches when the
    /// menu bar's height isn't known.
    static let zoneDepth: CGFloat = 34
    /// How far beyond the notch's sides it reaches.
    static let zoneMargin: CGFloat = 90
    /// Without a notch, the zone is this wide, centered.
    static let zoneWidthWithoutNotch: CGFloat = 360
    /// Within this distance of the top, a dragged window is "near" and the notch shows where to drop it.
    static let nearDepth: CGFloat = 220

    /// The drop zone at the top of one screen: the menu bar strip around the
    /// notch (or the middle of the top edge on a screen without one). A
    /// window can't be dragged into the menu bar, only the pointer can, so
    /// it never triggers by just moving a window up.
    static func zone(screen: CGRect, notchMinX: CGFloat?, notchMaxX: CGFloat?, menuBarHeight: CGFloat? = nil) -> CGRect {
        let minX: CGFloat, maxX: CGFloat
        if let notchMinX, let notchMaxX, notchMaxX > notchMinX {
            minX = notchMinX - zoneMargin
            maxX = notchMaxX + zoneMargin
        } else {
            minX = screen.midX - zoneWidthWithoutNotch / 2
            maxX = screen.midX + zoneWidthWithoutNotch / 2
        }
        let depth = menuBarHeight.map { max(zoneDepth, $0 + 4) } ?? zoneDepth
        return CGRect(x: max(screen.minX, minX), y: screen.minY,
                      width: min(screen.maxX, maxX) - max(screen.minX, minX), height: depth)
    }

    /// The area where a dragged window counts as near the drop zone.
    static func nearArea(around zone: CGRect) -> CGRect {
        CGRect(x: zone.minX - 160, y: zone.minY, width: zone.width + 320, height: nearDepth)
    }

    /// Without a record of the drag: whether the front window was pushed
    /// against the top (macOS stops it just under the menu bar) as the
    /// button came up in the zone.
    static func isPushedAgainstTop(_ frame: CGRect, screen: CGRect, menuBarHeight: CGFloat) -> Bool {
        abs(frame.minY - (screen.minY + menuBarHeight)) <= 12
    }

    /// Whether a mouse drag moved a window into a drop zone: the button went
    /// down on the window's title bar, the window moved, and the button came
    /// up inside a zone. (macOS stops the window at the menu bar, but the
    /// pointer goes on into the notch.)
    static func isDropIntoNotch(down: CGPoint, up: CGPoint, frameAtStart: CGRect, frameAtEnd: CGRect?, zones: [CGRect]) -> Bool {
        let titleBar = CGRect(x: frameAtStart.minX, y: frameAtStart.minY - 6, width: frameAtStart.width, height: 52)
        guard titleBar.contains(down), zones.contains(where: { $0.contains(up) }) else { return false }
        guard let frameAtEnd else { return false }
        return abs(frameAtEnd.minX - frameAtStart.minX) > 4 || abs(frameAtEnd.minY - frameAtStart.minY) > 4
    }

    /// Where the window started before the drag pushed it to the top, given
    /// where it was when the drag was first noticed and how far the pointer
    /// had moved by then.
    static func frameBeforeDrag(noticed: CGRect, pointerAtDown: CGPoint, pointerAtNotice: CGPoint) -> CGRect {
        noticed.offsetBy(dx: pointerAtDown.x - pointerAtNotice.x, dy: pointerAtDown.y - pointerAtNotice.y)
    }

    /// The size of a preview that fits `box`, keeping the window's shape.
    static func previewSize(for window: CGSize, fitting box: CGSize) -> CGSize {
        guard window.width > 0, window.height > 0 else { return box }
        let scale = min(box.width / window.width, box.height / window.height, 1)
        return CGSize(width: (window.width * scale).rounded(), height: (window.height * scale).rounded())
    }
}
