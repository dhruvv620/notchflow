// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Content unfolds out of the notch when it opens. Off: a plain fade.
    static let enableNotchMorph = Key<Bool>("enableNotchMorph", default: false)
}

/// Content that grows out of the notch instead of fading in after it.
///
/// The panel's shape already animates its size and corner radii; this makes
/// the content follow the same motion: it starts squeezed against the notch's
/// top edge, as narrow as the camera housing, and unfolds downward and outward
/// with a spring. Closing runs the same motion back into the notch.
/// Scale and opacity only: blurring the whole panel each frame costs too much.
struct NotchMorphEffect: ViewModifier, Animatable {
    /// 0 is folded into the notch, 1 is fully open.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = min(max(progress, 0), 1)
        content
            .scaleEffect(x: 0.55 + 0.45 * clamped, y: 0.25 + 0.75 * clamped, anchor: .top)
            .opacity(Double(clamped * clamped))
    }
}

extension AnyTransition {
    /// Unfolds from the notch on insertion, folds back on removal.
    @MainActor
    static var notchMorph: AnyTransition {
        // Off by choice, or Reduce Motion (NotchFlow's or the system's): a plain cross-fade.
        if !Defaults[.enableNotchMorph] || Defaults[.notchReduceMotion]
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .modifier(active: NotchMorphEffect(progress: 0), identity: NotchMorphEffect(progress: 1))
                .animation(NotchMorphMotion.unfold),
            removal: .modifier(active: NotchMorphEffect(progress: 0), identity: NotchMorphEffect(progress: 1))
                .animation(NotchMorphMotion.fold)
        )
    }
}

enum NotchMorphMotion {
    /// Slightly behind the shape, so the panel leads and the content follows.
    static let unfold = Animation.spring(response: 0.42, dampingFraction: 0.8).delay(0.03)
    static let fold = Animation.spring(response: 0.28, dampingFraction: 0.95)
}
