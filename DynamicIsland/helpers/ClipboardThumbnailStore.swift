// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO

/// Decode only a small preview, off the UI thread. Full clipboard data is kept for copying.
@MainActor
final class ClipboardThumbnailStore {
    static let shared = ClipboardThumbnailStore()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 40
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func image(for fileName: String) async -> NSImage? {
        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        let url = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
        let data = await Task.detached(priority: .utility) {
            Self.thumbnailData(at: url)
        }.value
        guard !Task.isCancelled, let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: fileName as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
    }

    private nonisolated static func thumbnailData(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
