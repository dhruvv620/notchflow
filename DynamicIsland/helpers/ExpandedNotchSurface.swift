// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Changes only the expanded surface. The notch's geometry and content stay upstream-owned.
struct ExpandedNotchSurface<Surface: Shape>: View {
    let shape: Surface
    let isExpanded: Bool
    let useLiquidGlass: Bool
    let cameraBandHeight: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded && useLiquidGlass && !reduceTransparency {
                glassSurface
                if cameraBandHeight > 0 {
                    Rectangle()
                        .fill(.black)
                        .frame(height: cameraBandHeight)
                }
            } else {
                Color.black
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glassSurface: some View {
        if #available(macOS 26.0, *) {
            // Use the supported SwiftUI material, without the private variant/KVO helper.
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)
                .environment(\.colorScheme, .dark)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.fill(.black.opacity(0.35)) }
                .environment(\.colorScheme, .dark)
        }
    }
}

#Preview("Classic and Liquid Glass") {
    VStack(spacing: 24) {
        previewSurface(glass: false)
        previewSurface(glass: true)
    }
    .padding(32)
    .background(Color.gray)
}

private func previewSurface(glass: Bool) -> some View {
    VStack(spacing: 12) {
        Text(glass ? "Liquid Glass" : "Classic")
            .font(.headline)
        Text("Atoll's original shape, spacing and content.")
            .font(.subheadline)
    }
    .foregroundStyle(.white)
    .frame(width: 420, height: 160)
    .background {
        ExpandedNotchSurface(
            shape: NotchShape(topCornerRadius: 6, bottomCornerRadius: 20),
            isExpanded: true,
            useLiquidGlass: glass,
            cameraBandHeight: 30
        )
    }
}
