// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The backing window can remain large for transitions. Its mouse region cannot.
enum NotchInputRegionPolicy {
    static func interactionRect(in bounds: CGRect, isExpanded: Bool, collapsedSize: CGSize?) -> CGRect {
        guard bounds.width > 0, bounds.height >= 0 else { return .zero }
        guard !isExpanded, let collapsedSize else { return bounds }
        let width = min(bounds.width, max(0, collapsedSize.width))
        let height = min(bounds.height, max(0, collapsedSize.height))
        // Retain a zero-height notch's horizontal span for hover activation.
        // The empty rectangle still never captures a native mouse event.
        guard width > 0 else { return .zero }
        return CGRect(x: bounds.midX - width / 2, y: bounds.minY, width: width, height: height)
    }
}
