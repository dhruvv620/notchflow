// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO
import SwiftUI
import Defaults

@MainActor
final class FocusCompanionModel: ObservableObject {
    static let shared = FocusCompanionModel()
    @Published private(set) var sessionID: UUID?
    @Published private(set) var image: NSImage?
    @Published var error: String?
    private let imageURL: URL

    private init() {
        imageURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Focus/companion")
        image = NSImage(contentsOf: imageURL)
    }
    var isFocusSession: Bool {
        sessionID != nil && sessionID == TimerManager.shared.activeSessionID && TimerManager.shared.isTimerActive
    }
    func start(minutes: Double, focus: Bool) {
        Defaults[.enableTimerFeature] = true
        DynamicIslandViewCoordinator.shared.timerLiveActivityEnabled = true
        TimerManager.shared.startTimer(duration: minutes * 60, name: focus ? "Focus" : "Break")
        sessionID = TimerManager.shared.activeSessionID
    }
    func importImage(from url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= 10_000_000,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) <= 300,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 2048, height <= 2048 else {
                error = "Choose an image or GIF under 10 MB, 2048 × 2048 pixels and 300 frames."
                return
            }
            try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: url).write(to: imageURL, options: .atomic)
            image = NSImage(contentsOf: imageURL)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func resetImage() {
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) { try FileManager.default.removeItem(at: imageURL) }
            image = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
