// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

@main
struct WindowStashRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "WindowStashRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = WindowStashPolicy
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notchZone = P.zone(screen: laptop, notchMinX: 660, notchMaxX: 852)
        try require(notchZone == CGRect(x: 570, y: 0, width: 372, height: 34), "Notch zone: \(notchZone)")
        let menuBarZone = P.zone(screen: laptop, notchMinX: 660, notchMaxX: 852, menuBarHeight: 37)
        try require(menuBarZone.height == 41, "The zone covers the menu bar: \(menuBarZone)")
        try require(P.nearArea(around: notchZone).contains(CGPoint(x: 756, y: 150)), "Near area")
        try require(P.isPushedAgainstTop(CGRect(x: 100, y: 38, width: 800, height: 600), screen: laptop, menuBarHeight: 37)
                    && !P.isPushedAgainstTop(CGRect(x: 100, y: 200, width: 800, height: 600), screen: laptop, menuBarHeight: 37),
                    "Pushed against the top")
        // An external display to the right, without a notch.
        let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let plainZone = P.zone(screen: external, notchMinX: nil, notchMaxX: nil)
        try require(plainZone == CGRect(x: 2612, y: -200, width: 360, height: 34), "Zone without a notch: \(plainZone)")

        // Dragging Chrome by its title bar up into the notch.
        let start = CGRect(x: 200, y: 300, width: 900, height: 600)
        let end = CGRect(x: 420, y: 25, width: 900, height: 600)
        try require(P.isDropIntoNotch(down: CGPoint(x: 500, y: 312), up: CGPoint(x: 760, y: 10), frameAtStart: start,
                                      frameAtEnd: end, zones: [notchZone, plainZone]), "Drag into the notch missed")
        // Not when the pointer ends beside the notch, the window didn't move, or the drag began inside the window.
        try require(!P.isDropIntoNotch(down: CGPoint(x: 500, y: 312), up: CGPoint(x: 1200, y: 10), frameAtStart: start,
                                       frameAtEnd: end, zones: [notchZone]), "Drop beside the notch stashed")
        try require(!P.isDropIntoNotch(down: CGPoint(x: 500, y: 312), up: CGPoint(x: 760, y: 10), frameAtStart: start,
                                       frameAtEnd: start, zones: [notchZone]), "A window that didn't move was stashed")
        try require(!P.isDropIntoNotch(down: CGPoint(x: 500, y: 600), up: CGPoint(x: 760, y: 10), frameAtStart: start,
                                       frameAtEnd: end, zones: [notchZone]), "Selecting text up to the notch stashed the window")
        try require(!P.isDropIntoNotch(down: CGPoint(x: 500, y: 312), up: CGPoint(x: 760, y: 10), frameAtStart: start,
                                       frameAtEnd: nil, zones: [notchZone]), "A closed window was stashed")

        let before = P.frameBeforeDrag(noticed: CGRect(x: 205, y: 297, width: 900, height: 600),
                                       pointerAtDown: CGPoint(x: 500, y: 312), pointerAtNotice: CGPoint(x: 505, y: 309))
        try require(before == start, "Frame before the drag: \(before)")
        try require(P.previewSize(for: CGSize(width: 1600, height: 1000), fitting: CGSize(width: 120, height: 72))
                    == CGSize(width: 115, height: 72), "Preview size")
        print("Window stash: OK")
    }
}
