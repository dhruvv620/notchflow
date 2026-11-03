// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class DVAppearanceModel: ObservableObject {
    static let shared = DVAppearanceModel()
    @Published private(set) var gifURL: URL?
    @Published private(set) var errorMessage: String?
    private let directory: URL
    private let preferenceKey = "dv.idleGIF.filename"

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Animations", isDirectory: true)
        if let name = UserDefaults.standard.string(forKey: preferenceKey),
           name == (name as NSString).lastPathComponent {
            let saved = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: saved.path) { gifURL = saved }
        }
    }

    func chooseGIF(viewModel: DynamicIslandViewModel) {
        let token = UUID()
        let panel = NSOpenPanel()
        panel.title = "Choose an idle GIF"
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        viewModel.setAutoCloseSuppression(true, token: token)
        panel.begin { [weak self, weak viewModel] response in
            Task { @MainActor in
                defer { viewModel?.setAutoCloseSuppression(false, token: token) }
                guard response == .OK, let url = panel.url else { return }
                self?.importGIF(from: url)
            }
        }
    }

    private func importGIF(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let bytes = values.fileSize,
                  bytes <= 20 * 1024 * 1024,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let imageType = CGImageSourceGetType(source), imageType as String == UTType.gif.identifier,
                  CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 300,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber,
                  width.intValue > 0, height.intValue > 0,
                  width.intValue <= 2048, height.intValue <= 2048,
                  NSImage(contentsOf: url) != nil else {
                errorMessage = "Choose a GIF under 20 MB, up to 2048 x 2048 pixels and 300 frames."
                return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(UUID().uuidString + ".gif")
            try FileManager.default.copyItem(at: url, to: destination)
            let previous = gifURL
            UserDefaults.standard.set(destination.lastPathComponent, forKey: preferenceKey)
            gifURL = destination
            errorMessage = nil
            if let previous { try? FileManager.default.removeItem(at: previous) }
        } catch {
            errorMessage = "Could not import that GIF: " + error.localizedDescription
        }
    }

    func removeGIF() {
        if let gifURL { try? FileManager.default.removeItem(at: gifURL) }
        gifURL = nil
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: preferenceKey)
    }
}
