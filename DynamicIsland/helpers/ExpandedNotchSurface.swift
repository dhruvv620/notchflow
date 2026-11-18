// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

struct ExpandedNotchSurface<Surface: Shape>: View {
    let shape: Surface
    let isExpanded: Bool
    var styleOverride: NotchBackgroundStyle? = nil
    @Default(.notchBackgroundStyle) private var selectedStyle
    @Default(.notchOutline) private var outline
    @Default(.notchArtworkGlow) private var artworkGlow
    @Default(.notchGlassTone) private var glassTone
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: NotchBackgroundStyle { styleOverride ?? selectedStyle }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(isExpanded && style != .black && !reduceTransparency ? 0.01 : 1)
            if isExpanded && !reduceTransparency {
                surface
                if artworkGlow && coordinator.currentView == .home && style != .black {
                    RadialGradient(colors: [appearance.accentColor.opacity(0.15), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 440)
                }
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
                    .glassEffect(glass, in: shape)
                    .overlay { shape.fill(toneShade) }
                    .environment(\.colorScheme, toneScheme)
            } else { frosted }
        case .frosted: frosted
        }
    }
    private var frosted: some View {
        NotchFrostedMaterial()
            .overlay { shape.fill(frostedOverlay) }
            .environment(\.colorScheme, toneScheme)
    }

    // MARK: Glass tone

    @available(macOS 26.0, *)
    private var glass: Glass {
        switch glassTone {
        case .dark: return .regular.tint(.black.opacity(0.12))
        case .light: return .regular.tint(.white.opacity(0.22))
        case .tinted: return .regular.tint(appearance.accentColor.opacity(0.25))
        case .clear: return .clear.tint(.black.opacity(0.04))
        }
    }

    /// Light glass keeps a shade behind the text so white labels stay readable.
    private var toneShade: Color {
        glassTone == .light ? .black.opacity(0.2) : .clear
    }

    private var toneScheme: ColorScheme { glassTone == .light ? .light : .dark }

    private var frostedOverlay: Color {
        switch glassTone {
        case .dark: return .black.opacity(0.08)
        case .light: return .black.opacity(0.24)
        case .tinted: return appearance.accentColor.opacity(0.2)
        case .clear: return .clear
        }
    }
}

#Preview("Notch background choices") {
    VStack(spacing: 16) {
        ForEach(NotchBackgroundStyle.allCases) { style in
            Text(style.title).foregroundStyle(.white).frame(width: 340, height: 100)
                .background {
                    ExpandedNotchSurface(shape: NotchShape(topCornerRadius: 6, bottomCornerRadius: 28),
                                         isExpanded: true, styleOverride: style)
                }
        }
    }.padding().background(Color.gray)
}
