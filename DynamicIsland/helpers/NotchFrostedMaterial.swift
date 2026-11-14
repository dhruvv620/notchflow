// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Behind-window blending samples the desktop and other apps, rather than just
/// the notch's own content. The enclosing surface supplies the one shared mask.
struct NotchFrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> MaterialView {
        let view = MaterialView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: MaterialView, context: Context) {}
    final class MaterialView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
