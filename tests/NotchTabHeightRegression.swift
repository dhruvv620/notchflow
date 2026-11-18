// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

@main
struct NotchTabHeightRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotchTabHeightRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let compact: CGFloat = 200, spacious: CGFloat = 240

        // Preset tabs follow the user's panel size exactly.
        try require(NotchTabHeightPolicy.height(preset: compact, rule: .preset, reportedPanelHeight: nil) == 200, "Preset tab changed height")
        try require(NotchTabHeightPolicy.height(preset: spacious, rule: .preset, reportedPanelHeight: 400) == 240, "Preset tab followed a report")

        // Fixed-offset tabs (WhatsApp, Terminal).
        try require(NotchTabHeightPolicy.height(preset: compact, rule: .taller(by: 60), reportedPanelHeight: nil) == 260, "Taller tab not taller")
        try require(NotchTabHeightPolicy.height(preset: compact, rule: .taller(by: 60), reportedPanelHeight: 150) == 260, "Taller tab shrank to a report")

        // Floors (Timer needs 224 even in Compact).
        try require(NotchTabHeightPolicy.height(preset: compact, rule: .atLeast(224), reportedPanelHeight: nil) == 224, "Timer floor ignored")
        try require(NotchTabHeightPolicy.height(preset: spacious, rule: .atLeast(224), reportedPanelHeight: nil) == 240, "Floor shrank a larger preset")

        // Content-fitting tabs (Notifications) stay within their range.
        let fits = NotchTabHeightRule.fitsContent(shrinkBy: 40, growBy: 60)
        try require(NotchTabHeightPolicy.height(preset: compact, rule: fits, reportedPanelHeight: nil) == 200, "Unreported content tab not at preset")
        try require(NotchTabHeightPolicy.height(preset: compact, rule: fits, reportedPanelHeight: 120) == 160, "Short content not clamped to the minimum")
        try require(NotchTabHeightPolicy.height(preset: compact, rule: fits, reportedPanelHeight: 210.4) == 210, "Content height not followed")
        try require(NotchTabHeightPolicy.height(preset: compact, rule: fits, reportedPanelHeight: 900) == 260, "Tall content not clamped to the maximum")
        try require(NotchTabHeightPolicy.height(preset: compact, rule: fits, reportedPanelHeight: .infinity) == 160, "Infinite report accepted")
        let wide = NotchTabHeightRule.fitsContent(shrinkBy: 200, growBy: 0)
        try require(NotchTabHeightPolicy.height(preset: compact, rule: wide, reportedPanelHeight: 10) == NotchTabHeightPolicy.smallestPanel, "Panel shrank below the smallest usable size")

        // Reports are stepped so pixel jitter does not resize the notch.
        try require(NotchTabHeightPolicy.quantized(101) == 104 && NotchTabHeightPolicy.quantized(104) == 104, "Report not quantized up to the step")
        try require(NotchTabHeightPolicy.quantized(.nan) == 0, "NaN report not rejected")

        // Window resize ordering: grow now, shrink after the animation.
        try require(!NotchTabHeightPolicy.shouldDeferWindowResize(currentHeight: 200, targetHeight: 260), "Growing was deferred")
        try require(NotchTabHeightPolicy.shouldDeferWindowResize(currentHeight: 260, targetHeight: 200), "Shrinking was not deferred")
        try require(!NotchTabHeightPolicy.shouldDeferWindowResize(currentHeight: 200, targetHeight: 200), "Same size deferred")

        print("Tab height checks passed")
    }
}
