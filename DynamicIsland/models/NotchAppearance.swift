// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import ImageIO
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
    case adaptive, wallpaper, system, fixed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayName: String { title }
}
/// How the Glass and Frosted backgrounds are tinted.
enum NotchGlassTone: String, CaseIterable, Identifiable, Defaults.Serializable {
    case dark, light, tinted, clear
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
    static let notchGlassTone = Key<NotchGlassTone>("notchGlassTone", default: .dark)
    static let notchArtworkGlow = Key<Bool>("notchArtworkGlow", default: true)
    static let notchReduceMotion = Key<Bool>("notchReduceMotion", default: false)
    static let notchActivityIndicators = Key<Bool>("notchActivityIndicators", default: true)
    static let notchIndicatorStyle = Key<NotchIndicatorStyle>("notchIndicatorStyle", default: .dots)
}

@MainActor
final class NotchAppearanceModel: ObservableObject {
    static let shared = NotchAppearanceModel()
    @Published private(set) var accentColor: Color = .blue {
        // Older parts (timer icons, system indicators, HUDs) read the legacy
        // accent key; keep it equal to the accent chosen in Appearance.
        didSet { Defaults[.accentColor] = accentColor }
    }
    @Published private(set) var revision = 0
    /// A vibrant color picked from the desktop picture, when one can be read.
    @Published private(set) var wallpaperColor: NSColor?
    private var subscriptions = Set<AnyCancellable>()
    private var wallpaperSignature: String?
    private var wallpaperTask: Task<Void, Never>?

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
        // The desktop picture can change with the Space, the display or the
        // user; check on those occasions and every few minutes.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in true }
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in true })
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in true })
            .merge(with: Timer.publish(every: 300, on: .main, in: .common).autoconnect().map { _ in true })
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshWallpaperColor() }
            .store(in: &subscriptions)
        updateAccent()
        refreshWallpaperColor()
        DispatchQueue.main.async { music.calculateAverageColor() }
    }

    /// Reads the main display's desktop picture off the main thread and keeps
    /// its most vibrant color. Skipped when the picture has not changed.
    func refreshWallpaperColor() {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            wallpaperColor = nil
            updateAccent()
            return
        }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let signature = "\(url.path)@\(modified)"
        guard signature != wallpaperSignature else { return }
        wallpaperSignature = signature
        wallpaperTask?.cancel()
        wallpaperTask = Task.detached(priority: .utility) { [weak self] in
            let color = NotchWallpaperPalette.vibrantColor(of: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.wallpaperColor = color
                self?.updateAccent()
            }
        }
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
        case .wallpaper: accentColor = wallpaperAccent
        case .adaptive:
            // Album art while something plays, the desktop picture otherwise.
            let music = MusicManager.shared
            accentColor = music.isPlayerIdle ? wallpaperAccent : Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.6)
        }
    }

    private var wallpaperAccent: Color {
        guard let wallpaperColor else { return Color(nsColor: .controlAccentColor) }
        return Color(nsColor: wallpaperColor).ensureMinimumBrightness(factor: 0.6)
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

/// Picks a representative, vibrant color from an image file.
enum NotchWallpaperPalette {
    /// Samples a small thumbnail and returns the pixel that best balances
    /// saturation and brightness, so a grey sky does not win over a sunset.
    static func vibrantColor(of url: URL) -> NSColor? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 48,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let size = 16
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        var best: NSColor?
        var bestScore: CGFloat = -1
        var sum = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
        for index in 0..<(size * size) {
            let r = CGFloat(pixels[index * 4]) / 255
            let g = CGFloat(pixels[index * 4 + 1]) / 255
            let b = CGFloat(pixels[index * 4 + 2]) / 255
            sum = (sum.r + r, sum.g + g, sum.b + b)
            let color = NSColor(deviceRed: r, green: g, blue: b, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            guard brightness > 0.25 else { continue }
            let score = saturation * 0.7 + brightness * 0.3
            if score > bestScore {
                bestScore = score
                best = color
            }
        }
        // A monochrome picture has no vibrant pixel; use its average instead.
        if bestScore < 0.35 {
            let count = CGFloat(size * size)
            return NSColor(deviceRed: sum.r / count, green: sum.g / count, blue: sum.b / count, alpha: 1)
        }
        return best
    }
}

