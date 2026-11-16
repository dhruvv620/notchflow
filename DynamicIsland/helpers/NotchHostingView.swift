// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// AppDelegate owns the panel's screen-clamped frame. SwiftUI lays out inside
/// that frame instead of deriving a second window size from animated content.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureManualSizing()
    }

    required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        configureManualSizing()
    }

    private func configureManualSizing() {
        sizingOptions = []
        // The notch measures physical camera clearance from NSScreen itself.
        // Window-frame changes must not feed safe-area changes back into layout.
        safeAreaRegions = []
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
