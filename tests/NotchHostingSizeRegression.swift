// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
private final class HostingContentSize: ObservableObject {
    @Published var expanded = false
}

private struct ChangingHostingContent: View {
    @ObservedObject var model: HostingContentSize
    var body: some View {
        Text("Animated notch content")
            .frame(width: model.expanded ? 780 : 210,
                   height: model.expanded ? 320 : 32)
            .animation(.easeInOut(duration: 0.005), value: model.expanded)
    }
}

@main
struct NotchHostingSizeRegression {
    @MainActor static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotchHostingSizeRegression", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = HostingContentSize()
        let hosting = FirstMouseHostingView(rootView: ChangingHostingContent(model: model))
        try require(hosting.sizingOptions.isEmpty, "SwiftUI can impose a second panel size")
        try require(hosting.safeAreaRegions.isEmpty, "Panel resize still feeds safe-area changes into SwiftUI")
        try require(hosting.acceptsFirstMouse(for: nil), "First-click behavior was lost")
        let window = NSPanel(contentRect: NSRect(x: 100, y: 300, width: 640, height: 240),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }

        // This is the crash's actual interaction: AppKit lays out the hosting
        // view while its content animates to a different ideal size, and the
        // explicit window owner simultaneously selects another bounded frame.
        for index in 0..<20 {
            model.expanded = index.isMultiple(of: 2)
            let size = index.isMultiple(of: 3) ? NSSize(width: 720, height: 240) : NSSize(width: 640, height: 200)
            let target = NSRect(x: 100, y: 600 - size.height, width: size.width, height: size.height)
            window.setFrame(target, display: false)
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
            try require(window.frame == target, "Animated SwiftUI content resized the explicitly sized panel")
            try require(hosting.frame.size == window.contentRect(forFrameRect: target).size,
                        "Hosting content stopped following the parent frame")
        }

        // Display changes used to destroy every notch panel while SwiftUI was
        // in an animated layout pass. Exercise the safe ownership sequence used
        // for a removed display: keep the surviving panel alive, detach the
        // removed panel's hosted tree, and only then close it. Repeating this
        // also catches AppKit layout feedback that only appears after several
        // open/close cycles.
        for index in 0..<20 {
            model.expanded.toggle()
            let secondaryModel = HostingContentSize()
            let secondaryHosting = FirstMouseHostingView(
                rootView: ChangingHostingContent(model: secondaryModel)
            )
            let secondaryWindow = NSPanel(
                contentRect: NSRect(x: 900, y: 300, width: 640, height: 240),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            secondaryWindow.isReleasedWhenClosed = false
            secondaryWindow.contentView = secondaryHosting
            secondaryWindow.orderFrontRegardless()

            secondaryModel.expanded = true
            secondaryWindow.setFrame(
                NSRect(x: 900, y: 280, width: 720, height: 280),
                display: false
            )
            secondaryWindow.layoutIfNeeded()
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))

            secondaryWindow.contentView = nil
            secondaryWindow.orderOut(nil)
            secondaryWindow.close()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))

            try require(secondaryWindow.contentView == nil,
                        "Removed-display panel retained its SwiftUI hosting tree")
            try require(window.contentView === hosting,
                        "Removing one display disturbed the surviving panel")
            try require(window.isVisible,
                        "Removing one display closed the surviving panel")
            try require(!index.isMultiple(of: 5) || hosting.sizingOptions.isEmpty,
                        "Repeated panel churn restored implicit hosting sizing")
        }
        print("Native hosting size ownership, animated layout, and repeated panel teardown checks passed")
    }
}
