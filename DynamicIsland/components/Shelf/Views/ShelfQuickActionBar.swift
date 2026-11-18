// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// One-click actions for the selected Shelf files: resize, PDF, compress,
/// remove background, AirDrop and send to a WhatsApp chat. Results land back
/// on the Shelf as new items.
struct ShelfQuickActionBar: View {
    @ObservedObject private var selection = ShelfSelectionModel.shared
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var busyAction: String?
    @State private var message: String?

    private var selectedFiles: [ShelfItem] {
        selection.selectedItems(in: shelf.items).filter {
            if case .file = $0.kind { return true }
            return false
        }
    }

    private var hasImages: Bool {
        selectedFiles.contains { item in
            guard let url = item.fileURL else { return false }
            return ImageProcessingService.shared.isImageFile(url)
        }
    }

    var body: some View {
        if !selectedFiles.isEmpty {
            HStack(spacing: 6) {
                Text(selectedFiles.count == 1 ? "1 file" : "\(selectedFiles.count) files")
                    .font(NotchTokens.Typography.captionEmphasis)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                if hasImages {
                    Menu {
                        Button("Half Size") { run("Resize") { try await ShelfQuickActions.resize(selectedFiles, scale: 0.5) } }
                        Button("Fit 2048 px") { run("Resize") { try await ShelfQuickActions.resize(selectedFiles, maxDimension: 2048) } }
                        Button("Fit 1080 px") { run("Resize") { try await ShelfQuickActions.resize(selectedFiles, maxDimension: 1080) } }
                    } label: {
                        actionLabel("Resize", symbol: "arrow.down.right.and.arrow.up.left")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    actionButton("PDF", symbol: "doc.richtext") { try await ShelfQuickActions.makePDF(selectedFiles) }

                    if selectedFiles.count == 1 {
                        actionButton("Cut Out", symbol: "person.crop.rectangle") { try await ShelfQuickActions.removeBackground(selectedFiles) }
                    }
                }

                actionButton("Zip", symbol: "doc.zipper") { try await ShelfQuickActions.compress(selectedFiles) }
                actionButton("AirDrop", symbol: "airplayaudio") { try await ShelfQuickActions.airDrop(selectedFiles) }

                if whatsApp.state.isConnected, !whatsApp.visibleChats.isEmpty {
                    Menu {
                        ForEach(whatsApp.visibleChats.prefix(8)) { chat in
                            Button(chat.displayName) {
                                run("WhatsApp") { try await ShelfQuickActions.sendToWhatsApp(selectedFiles, chatID: chat.id, chatName: chat.displayName) }
                            }
                        }
                    } label: {
                        actionLabel("WhatsApp", symbol: "message.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                if busyAction != nil {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(NotchTokens.Typography.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .offset(y: -24)
                        .transition(.opacity)
                }
            }
            .environment(\.colorScheme, .dark)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .disabled(busyAction != nil)
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(NotchTokens.Typography.captionEmphasis)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func actionButton(_ title: String, symbol: String, work: @escaping @MainActor () async throws -> String?) -> some View {
        Button { run(title, work: work) } label: { actionLabel(title, symbol: symbol) }
            .buttonStyle(.plain)
    }

    private func run(_ title: String, work: @escaping @MainActor () async throws -> String?) {
        guard busyAction == nil else { return }
        busyAction = title
        Task { @MainActor in
            do {
                let result = try await work()
                show(result ?? "\(title) done")
            } catch {
                show(error.localizedDescription)
            }
            busyAction = nil
        }
    }

    private func show(_ text: String) {
        withAnimation(NotchTokens.Motion.standard) { message = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(NotchTokens.Motion.standard) { if message == text { message = nil } }
        }
    }
}

enum ShelfQuickActionError: LocalizedError {
    case nothingToDo(String)
    var errorDescription: String? {
        if case .nothingToDo(let detail) = self { return detail }
        return nil
    }
}

/// The work behind the quick action bar.
@MainActor
enum ShelfQuickActions {
    private static func fileURLs(_ items: [ShelfItem]) async -> [URL] {
        await ShelfStateViewModel.shared.resolveFileURLsAsync(for: items)
    }

    private static func addToShelf(_ urls: [URL]) {
        let items = urls.compactMap { url -> ShelfItem? in
            guard let bookmark = try? Bookmark(url: url) else { return nil }
            return ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)
        }
        if !items.isEmpty { ShelfStateViewModel.shared.add(items) }
    }

    static func resize(_ items: [ShelfItem], scale: CGFloat? = nil, maxDimension: CGFloat? = nil) async throws -> String? {
        let images = await fileURLs(items).filter { ImageProcessingService.shared.isImageFile($0) }
        guard !images.isEmpty else { throw ShelfQuickActionError.nothingToDo("Select an image to resize.") }
        var results: [URL] = []
        for url in images {
            let output = try await url.accessSecurityScopedResource { accessible -> URL? in
                var target = maxDimension
                if let scale, let image = NSImage(contentsOf: accessible) {
                    let pixels = image.representations.map { CGFloat(max($0.pixelsWide, $0.pixelsHigh)) }.max() ?? max(image.size.width, image.size.height)
                    target = max(16, (pixels * scale).rounded())
                }
                let format: ImageConversionOptions.ImageFormat = accessible.pathExtension.lowercased() == "png" ? .png : .jpeg
                let options = ImageConversionOptions(format: format, compressionQuality: 0.88, maxDimension: target, removeMetadata: false)
                return try await ImageProcessingService.shared.convertImage(from: accessible, options: options)
            }
            if let output { results.append(output) }
        }
        addToShelf(results)
        return results.count == 1 ? "Resized copy added" : "\(results.count) resized copies added"
    }

    static func makePDF(_ items: [ShelfItem]) async throws -> String? {
        let images = await fileURLs(items).filter { ImageProcessingService.shared.isImageFile($0) }
        guard !images.isEmpty else { throw ShelfQuickActionError.nothingToDo("Select images to combine into a PDF.") }
        let pdf = try await images.accessSecurityScopedResources { urls in
            try await ImageProcessingService.shared.createPDF(from: urls)
        }
        if let pdf { addToShelf([pdf]) }
        return "PDF added to the Shelf"
    }

    static func removeBackground(_ items: [ShelfItem]) async throws -> String? {
        guard let image = await fileURLs(items).first(where: { ImageProcessingService.shared.isImageFile($0) }) else {
            throw ShelfQuickActionError.nothingToDo("Select an image.")
        }
        let output = try await image.accessSecurityScopedResource { url in
            try await ImageProcessingService.shared.removeBackground(from: url)
        }
        if let output { addToShelf([output]) }
        return "Cut-out added to the Shelf"
    }

    static func compress(_ items: [ShelfItem]) async throws -> String? {
        let urls = await fileURLs(items)
        guard !urls.isEmpty else { throw ShelfQuickActionError.nothingToDo("These files are no longer available.") }
        let zip = await urls.accessSecurityScopedResources { accessible in
            await TemporaryFileStorageService.shared.createZip(from: accessible)
        }
        guard let zip else { throw ShelfQuickActionError.nothingToDo("The archive could not be created.") }
        addToShelf([zip])
        return "Zip added to the Shelf"
    }

    static func airDrop(_ items: [ShelfItem]) async throws -> String? {
        let urls = await fileURLs(items)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else {
            throw ShelfQuickActionError.nothingToDo("AirDrop is not available.")
        }
        let accessing = urls.filter { $0.startAccessingSecurityScopedResource() }
        guard service.canPerform(withItems: urls) else {
            accessing.forEach { $0.stopAccessingSecurityScopedResource() }
            throw ShelfQuickActionError.nothingToDo("AirDrop cannot send these items.")
        }
        service.perform(withItems: urls)
        // AirDrop reads the files while its sheet is open.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            accessing.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        return nil
    }

    static func sendToWhatsApp(_ items: [ShelfItem], chatID: String, chatName: String) async throws -> String? {
        let urls = await fileURLs(items)
        guard !urls.isEmpty else { throw ShelfQuickActionError.nothingToDo("These files are no longer available.") }
        let sent = await urls.accessSecurityScopedResources { accessible in
            await WhatsAppManager.shared.sendFiles(accessible, to: chatID)
        }
        guard sent else {
            throw ShelfQuickActionError.nothingToDo(WhatsAppManager.shared.lastSendError ?? "WhatsApp did not send the files.")
        }
        return urls.count == 1 ? "Sent to \(chatName)" : "\(urls.count) files sent to \(chatName)"
    }
}
