// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Defaults
import SwiftUI

enum NotchBackgroundStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case black, dynamic, glass, frosted
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayName: String { title }
}
enum NotchElementStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case subtle, graphite, gradient
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayName: String { title }
}
enum NotchSizePreset: String, CaseIterable, Identifiable, Defaults.Serializable {
    case compact, spacious, custom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayName: String { title }
}
enum NotchAccentMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case adaptive, system, fixed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayName: String { title }
}
enum NotchIndicatorStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case dots, icons
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayName: String { title }
}

extension Defaults.Keys {
    static let notchBackgroundStyle = Key<NotchBackgroundStyle>("notchBackgroundStyle", default: .black)
    static let notchElementStyle = Key<NotchElementStyle>("notchElementStyle", default: .subtle)
    static let notchSizePreset = Key<NotchSizePreset>("notchSizePreset", default: .compact)
    static let notchCustomHeight = Key<Double>("notchCustomHeight", default: 240)
    static let notchCornerRadius = Key<Double>("notchCornerRadius", default: 28)
    static let notchOutline = Key<Bool>("notchOutline", default: false)
    static let notchAccentMode = Key<NotchAccentMode>("notchAccentMode", default: .adaptive)
    static let notchFixedAccentColor = Key<Color>("notchFixedAccentColor", default: .blue)
    static let notchArtworkGlow = Key<Bool>("notchArtworkGlow", default: true)
    static let notchReduceMotion = Key<Bool>("notchReduceMotion", default: false)
    static let notchActivityIndicators = Key<Bool>("notchActivityIndicators", default: true)
    static let notchIndicatorStyle = Key<NotchIndicatorStyle>("notchIndicatorStyle", default: .dots)
}

@MainActor
final class NotchAppearanceModel: ObservableObject {
    static let shared = NotchAppearanceModel()
    @Published private(set) var accentColor: Color = .blue
    @Published private(set) var revision = 0
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        // Migrate the prior single glass switch once, without discarding a user's choice.
        let preferences = UserDefaults.standard
        if !preferences.bool(forKey: "notchAppearanceModesMigrated.v1") {
            if preferences.object(forKey: "notchBackgroundStyle") == nil && Defaults[.expandedNotchLiquidGlass] {
                Defaults[.notchBackgroundStyle] = .glass
            }
            preferences.set(true, forKey: "notchAppearanceModesMigrated.v1")
        }
        let music = MusicManager.shared
        music.$avgColor.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateAccent() }.store(in: &subscriptions)
        music.$isPlayerIdle.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateAccent() }.store(in: &subscriptions)
        Defaults.publisher(.notchAccentMode, options: []).sink { [weak self] _ in
            self?.updateAccent()
            DispatchQueue.main.async { music.calculateAverageColor() }
        }.store(in: &subscriptions)
        Defaults.publisher(.notchFixedAccentColor, options: []).sink { [weak self] _ in self?.updateAccent() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.updateAccent() }.store(in: &subscriptions)
        // The model also makes computed layout helpers reactive to shared appearance settings.
        Publishers.MergeMany([
            Defaults.publisher(.notchSizePreset, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.notchCustomHeight, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.notchCornerRadius, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.notchBackgroundStyle, options: []).map { _ in true }.eraseToAnyPublisher()
        ]).receive(on: RunLoop.main).sink { [weak self] _ in self?.revision += 1 }.store(in: &subscriptions)
        updateAccent()
        DispatchQueue.main.async { music.calculateAverageColor() }
    }

    var accentForegroundColor: Color {
        guard let rgb = NSColor(accentColor).usingColorSpace(.deviceRGB) else { return .white }
        let luminance = rgb.redComponent * 0.299 + rgb.greenComponent * 0.587 + rgb.blueComponent * 0.114
        return luminance > 0.6 ? .black : .white
    }

    private func updateAccent() {
        switch Defaults[.notchAccentMode] {
        case .system: accentColor = Color(nsColor: .controlAccentColor)
        case .fixed: accentColor = Defaults[.notchFixedAccentColor]
        case .adaptive:
            let music = MusicManager.shared
            accentColor = music.isPlayerIdle ? Color(nsColor: .controlAccentColor) : Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.6)
        }
    }
}

/// Shared card treatment; semantic text/list colors remain separate from the accent.
struct NotchElementSurface: View {
    var cornerRadius: CGFloat = 10
    @Default(.notchElementStyle) private var style
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill)
            .allowsHitTesting(false)
    }
    private var fill: AnyShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(white: style == .subtle ? 0.06 : 0.12)) }
        switch style {
        case .subtle: return AnyShapeStyle(Color.white.opacity(0.035))
        case .graphite: return AnyShapeStyle(Color.white.opacity(0.09))
        case .gradient:
            return AnyShapeStyle(LinearGradient(colors: [appearance.accentColor.opacity(0.18), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
