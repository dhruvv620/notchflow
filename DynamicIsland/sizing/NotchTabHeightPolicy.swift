// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import CoreGraphics
import Foundation

/// How tall one tab wants the open notch to be, relative to the panel size
/// the user chose (Compact, Spacious or Custom).
///
/// Pure geometry: no UI, no settings, so Build.command can check it alone.
struct NotchTabHeightRule: Equatable, Sendable {
    /// Lowest height, as an offset from the preset height (may be negative).
    var minimumOffset: CGFloat
    /// Highest height, as an offset from the preset height.
    var maximumOffset: CGFloat
    /// Height used when the tab has not reported its content.
    var defaultOffset: CGFloat
    /// An absolute floor the tab cannot work below, whatever the preset.
    var absoluteMinimum: CGFloat?

    /// Exactly the preset height.
    static let preset = NotchTabHeightRule(minimumOffset: 0, maximumOffset: 0, defaultOffset: 0)

    /// The preset height plus a fixed amount.
    static func taller(by offset: CGFloat) -> NotchTabHeightRule {
        NotchTabHeightRule(minimumOffset: offset, maximumOffset: offset, defaultOffset: offset)
    }

    /// At least `minimum` points, otherwise the preset height.
    static func atLeast(_ minimum: CGFloat) -> NotchTabHeightRule {
        NotchTabHeightRule(minimumOffset: 0, maximumOffset: 0, defaultOffset: 0, absoluteMinimum: minimum)
    }

    /// Follows the tab's reported content, within these offsets from the preset.
    static func fitsContent(shrinkBy: CGFloat, growBy: CGFloat, defaultOffset: CGFloat = 0) -> NotchTabHeightRule {
        NotchTabHeightRule(minimumOffset: -abs(shrinkBy), maximumOffset: abs(growBy), defaultOffset: defaultOffset)
    }
}

enum NotchTabHeightPolicy {
    /// No open notch is shorter than this, so the header and one row always fit.
    static let smallestPanel: CGFloat = 140

    /// The open notch height for a tab.
    /// - Parameters:
    ///   - preset: The height of the user's panel size.
    ///   - rule: The tab's rule.
    ///   - reportedPanelHeight: The full panel height the tab's content asks
    ///     for (content plus the notch header), when it reports one.
    static func height(preset: CGFloat, rule: NotchTabHeightRule, reportedPanelHeight: CGFloat?) -> CGFloat {
        let lower = max(preset + rule.minimumOffset, rule.absoluteMinimum ?? 0, smallestPanel)
        let upper = max(lower, preset + rule.maximumOffset)
        let wanted = reportedPanelHeight ?? (preset + rule.defaultOffset)
        guard wanted.isFinite else { return lower.rounded() }
        return min(max(wanted, lower), upper).rounded()
    }

    /// The tallest the tab can get, whatever its content reports. The window
    /// is kept this tall while the notch is open, so switching tabs only
    /// animates the panel inside it and never resizes the window.
    static func tallest(preset: CGFloat, rule: NotchTabHeightRule) -> CGFloat {
        let lower = max(preset + rule.minimumOffset, rule.absoluteMinimum ?? 0, smallestPanel)
        return max(lower, preset + rule.maximumOffset).rounded()
    }

    /// Reported heights are rounded up to a small step, so a list that moves
    /// by a pixel does not resize the notch on every layout pass.
    static func quantized(_ height: CGFloat, step: CGFloat = 4) -> CGFloat {
        guard height.isFinite, height > 0, step > 0 else { return 0 }
        return (height / step).rounded(.up) * step
    }

    /// Growing must enlarge the window first, so the panel has room to animate
    /// into. Shrinking must wait until the panel has finished animating, or the
    /// window clips it mid-way.
    static func shouldDeferWindowResize(currentHeight: CGFloat, targetHeight: CGFloat) -> Bool {
        targetHeight < currentHeight - 0.5
    }

    /// How long the panel's height animation runs, and how long a shrinking
    /// window waits for it.
    static let animationDuration: Double = 0.3
}
