// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

struct ExpandedNotchSurface<Surface: Shape>: View {
    let shape: Surface
    let isExpanded: Bool
    let cameraBandHeight: CGFloat
    var styleOverride: NotchBackgroundStyle? = nil
    @Default(.notchBackgroundStyle) private var selectedStyle
    @Default(.notchOutline) private var outline
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: NotchBackgroundStyle { styleOverride ?? selectedStyle }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(isExpanded && style != .black && !reduceTransparency ? 0.01 : 1)
            if isExpanded && !reduceTransparency {
                surface
                if cameraBandHeight > 0 { Color.black.frame(height: cameraBandHeight) }
            }
        }
        .clipShape(shape)
        .overlay {
            if isExpanded && outline {
                shape.stroke(appearance.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var surface: some View {
        switch style {
        case .black: Color.black
        case .dynamic:
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.15),
                .init(color: appearance.accentColor.opacity(0.28), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .background(.black)
        case .glass:
            if #available(macOS 26.0, *) {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)
                    .environment(\.colorScheme, .dark)
            } else { frosted }
        case .frosted: frosted
        }
    }
    private var frosted: some View {
        shape.fill(.regularMaterial)
            .overlay { shape.fill(.black.opacity(0.3)) }
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Notch background choices") {
    VStack(spacing: 16) {
        ForEach(NotchBackgroundStyle.allCases) { style in
            Text(style.title).foregroundStyle(.white).frame(width: 340, height: 100)
                .background {
                    ExpandedNotchSurface(shape: NotchShape(topCornerRadius: 6, bottomCornerRadius: 28),
                                         isExpanded: true, cameraBandHeight: 20, styleOverride: style)
                }
        }
    }.padding().background(Color.gray)
}
