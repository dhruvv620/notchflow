// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

@main
struct NotchInputRegionRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotchInputRegionRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let expanded = CGRect(x: 0, y: 0, width: 640, height: 240)
        let collapsed = NotchInputRegionPolicy.interactionRect(in: expanded, isExpanded: false,
                                                              collapsedSize: CGSize(width: 220, height: 32))
        try require(!collapsed.contains(CGPoint(x: 320, y: 100)), "Collapsed panel kept its old expanded input area")
        try require(!collapsed.contains(CGPoint(x: 40, y: 15)), "Collapsed panel blocked menu-bar space beside the notch")
        try require(collapsed.contains(CGPoint(x: 320, y: 15)), "Visible closed notch stopped receiving input")
        let open = NotchInputRegionPolicy.interactionRect(in: expanded, isExpanded: true,
                                                         collapsedSize: CGSize(width: 220, height: 32))
        try require(open.contains(CGPoint(x: 320, y: 100)), "Expanded controls became pass-through")
        let bounds = CGRect(x: 0, y: 0, width: 180, height: 24)
        let clamped = NotchInputRegionPolicy.interactionRect(in: bounds, isExpanded: false,
                                                            collapsedSize: CGSize(width: 220, height: 32))
        try require(clamped == bounds, "Closed input extended beyond the actual visible view")
        let hidden = NotchInputRegionPolicy.interactionRect(in: CGRect(x: 0, y: 0, width: 220, height: 0),
                                                            isExpanded: false,
                                                            collapsedSize: CGSize(width: 220, height: 0))
        try require(hidden.width == 220 && hidden.isEmpty, "Zero-height notch must retain hover width without capturing clicks")
        let shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14).path(in: collapsed)
        try require(shape.contains(CGPoint(x: collapsed.midX, y: 15)), "Closed shape rejected its center")
        try require(!shape.contains(CGPoint(x: collapsed.minX + 1, y: 15)), "Transparent clipped edge captured a click")
        print("Visible-notch input region checks passed")
    }
}
