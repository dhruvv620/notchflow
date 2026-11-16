// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

/// Notch appearance controls share the existing settings form and preference store.
struct NotchAppearanceSettingsSection: View {
    var highlightID: (String) -> String = { $0 }

    @Default(.notchElementStyle) private var elementStyle
    @Default(.notchSizePreset) private var sizePreset
    @Default(.openNotchWidth) private var customWidth
    @Default(.notchCustomHeight) private var customHeight
    @Default(.notchCornerRadius) private var cornerRadius
    @Default(.notchBackgroundStyle) private var backgroundStyle
    @Default(.notchOutline) private var outline
    @Default(.notchAccentMode) private var accentMode
    @Default(.notchFixedAccentColor) private var fixedAccent
    @Default(.notchArtworkGlow) private var artworkGlow
    @Default(.notchReduceMotion) private var reduceMotion
    @Default(.notchActivityIndicators) private var activityIndicators
    @Default(.notchIndicatorStyle) private var indicatorStyle
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private let swatches: [(name: String, color: Color)] = [
        ("White", .white), ("Blue", .blue), ("Purple", .purple), ("Pink", .pink),
        ("Green", .green), ("Orange", .orange), ("Cyan", .cyan)
    ]

    private var customWidthRange: ClosedRange<Double> {
        let maximum = max(360, min(1000, Double(maxAllowedNotchWidth())))
        return min(480, maximum)...maximum
    }
    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(customWidth) },
            set: { customWidth = CGFloat(min(max($0, customWidthRange.lowerBound), customWidthRange.upperBound)) }
        )
    }
    private var colorBinding: Binding<Color> {
        Binding(get: { fixedAccent }, set: { fixedAccent = $0; accentMode = .fixed })
    }

    var body: some View {
        Group {
            elementsSection
            islandSection
            accentSection
            motionSection
            carouselSection
        }
    }

    private var elementsSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(NotchElementStyle.allCases) { style in
                    Button { elementStyle = style } label: {
                        VStack(spacing: 8) {
                            elementPreview(style)
                                .frame(height: 52)
                            Text(style.title)
                                .font(.callout.weight(elementStyle == style ? .semibold : .regular))
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(elementStyle == style ? Color.accentColor : .clear, lineWidth: 2)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.title) element style")
                    .accessibilityAddTraits(elementStyle == style ? .isSelected : [])
                }
            }
            .settingsHighlight(id: highlightID("Element style"))
            Text("Choose the surface used for cards and controls inside the notch.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("Elements") }
    }

    private func elementPreview(_ style: NotchElementStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.black)
            Group {
                switch style {
                case .subtle:
                    RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.065))
                case .graphite:
                    RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.14))
                case .gradient:
                    RoundedRectangle(cornerRadius: 9).fill(
                        LinearGradient(colors: [Color(white: 0.20), Color(white: 0.035)], startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
        }
    }

    private var islandSection: some View {
        Section {
            HStack {
                Text("Size")
                Spacer(minLength: 16)
                Picker("Island size", selection: $sizePreset) {
                    ForEach(NotchSizePreset.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 340)
            }
            .settingsHighlight(id: highlightID("Island size"))

            if sizePreset == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    measurementLabel("Width", value: Double(customWidth))
                    Slider(value: widthBinding, in: customWidthRange, step: 10)
                        .accessibilityLabel("Custom island width")
                    measurementLabel("Height", value: customHeight)
                    Slider(value: $customHeight, in: 200...420, step: 10)
                        .accessibilityLabel("Custom island height")
                }
                .settingsHighlight(id: highlightID("Custom island size"))
            }

            VStack(alignment: .leading, spacing: 8) {
                measurementLabel("Corner radius", value: cornerRadius)
                Slider(value: $cornerRadius, in: 0...48, step: 1)
                    .accessibilityLabel("Island corner radius")
            }
            .settingsHighlight(id: highlightID("Corner radius"))

            HStack {
                Text("Background")
                Spacer(minLength: 16)
                Picker("Island background", selection: $backgroundStyle) {
                    ForEach(NotchBackgroundStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 400)
            }
            .settingsHighlight(id: highlightID("Island background"))
            Text(backgroundDescription)
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Outline", isOn: $outline).toggleStyle(.switch)
                .settingsHighlight(id: highlightID("Island outline"))
        } header: { Text("Island") }
    }

    private var backgroundDescription: String {
        switch backgroundStyle {
        case .black: return "An opaque black surface that blends into the camera area."
        case .dynamic: return "The expanded surface follows the current accent color."
        case .glass: return "Native Liquid Glass on macOS 26 or later, with a frosted fallback on earlier versions."
        case .frosted: return "A softly blurred surface behind the notch content."
        }
    }

    private func measurementLabel(_ title: String, value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.rounded())) pt")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var accentSection: some View {
        Section {
            Picker("Accent color", selection: $accentMode) {
                ForEach(NotchAccentMode.allCases) { Text($0.title).tag($0) }
            }
            .settingsHighlight(id: highlightID("Notch accent color"))
            HStack(spacing: 12) {
                ForEach(swatches, id: \.name) { swatch in
                    Button {
                        fixedAccent = swatch.color
                        accentMode = .fixed
                    } label: {
                        Circle().fill(swatch.color)
                            .frame(width: 25, height: 25)
                            .overlay {
                                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
                            }
                            .overlay {
                                if accentMode == .fixed && colorsMatch(fixedAccent, swatch.color) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(swatch.name == "White" ? .black : .white)
                                }
                            }
                            .padding(2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(swatch.name) accent color")
                    .help("Use \(swatch.name.lowercased()) accent")
                }
                Spacer(minLength: 8)
                ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden().help("Choose a custom accent color")
            }
            Text(accentMode == .adaptive
                 ? "Adaptive uses the current artwork color for playback, the visualizer and notch controls."
                 : "The selected accent is shared by the notch's controls and playback elements.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Artwork glow", isOn: $artworkGlow).toggleStyle(.switch)
                .settingsHighlight(id: highlightID("Artwork glow"))
        } header: { Text("Accent") }
    }

    private func colorsMatch(_ first: Color, _ second: Color) -> Bool {
        guard let lhs = NSColor(first).usingColorSpace(.deviceRGB),
              let rhs = NSColor(second).usingColorSpace(.deviceRGB) else { return false }
        return abs(lhs.redComponent - rhs.redComponent) < 0.02
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.02
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.02
    }

    private var motionSection: some View {
        Section {
            Toggle("Reduce motion", isOn: $reduceMotion).toggleStyle(.switch)
                .settingsHighlight(id: highlightID("Reduce notch motion"))
            if systemReduceMotion {
                Text("Reduce Motion is also enabled in macOS Accessibility settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Motion") }
    }

    private var carouselSection: some View {
        Section {
            Toggle("Activity dots", isOn: $activityIndicators).toggleStyle(.switch)
                .settingsHighlight(id: highlightID("Activity indicators"))
            HStack {
                Text("Style")
                Spacer()
                Picker("Activity indicator style", selection: $indicatorStyle) {
                    ForEach(NotchIndicatorStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 180)
                .disabled(!activityIndicators)
            }
        } header: { Text("Carousel") }
    }
}

#Preview("Notch Appearance") {
    Form { NotchAppearanceSettingsSection() }
        .formStyle(.grouped)
        .frame(width: 650, height: 820)
}
