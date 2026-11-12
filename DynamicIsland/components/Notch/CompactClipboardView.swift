// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

/// Recent copies stay inside the existing notch bounds; pagination replaces expansion.
struct CompactClipboardView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = ClipboardManager.shared
    @Default(.enableClipboardManager) private var enabled
    @State private var filter: CompactClipboardKind = .all
    @State private var page = 0
    @State private var copiedID: UUID?
    @State private var copyFailed = false
    @State private var clearConfirmation = false
    @State private var interactionToken = UUID()

    private var items: [ClipboardItem] {
        let recent = Array(manager.regularHistory.prefix(ClipboardManager.historyLimit))
        return filter == .all ? recent : recent.filter { kind(of: $0) == filter }
    }
    private func kind(of item: ClipboardItem) -> CompactClipboardKind {
        CompactClipboardPolicy.kind(type: item.type.rawValue, text: item.stringData.map { String($0.prefix(4096)) })
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, min(5, Int(max(1, geometry.size.width - 24) / 108)))
            let count = CompactClipboardPolicy.pageCount(itemCount: items.count, pageSize: columns)
            let currentPage = CompactClipboardPolicy.clampedPage(page, itemCount: items.count, pageSize: columns)
            let range = CompactClipboardPolicy.range(page: currentPage, itemCount: items.count, pageSize: columns)
            VStack(spacing: 6) {
                HStack {
                    Text("Clipboard").font(.system(size: 13, weight: .semibold))
                    if copiedID != nil {
                        Label("Copied", systemImage: "checkmark").font(.caption2).foregroundStyle(.green)
                    } else if copyFailed {
                        Text("Could not copy this item").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("\(manager.regularHistory.count) / \(ClipboardManager.historyLimit)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            ForEach(CompactClipboardKind.filters) { value in filterButton(value) }
                        }.fixedSize(horizontal: true, vertical: false)
                        Menu {
                            ForEach(CompactClipboardKind.filters) { value in
                                Button(value.label) { filter = value }
                            }
                        } label: { Label(filter.label, systemImage: filter.symbol) }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    Spacer(minLength: 2)
                    HStack(spacing: 3) {
                        Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(currentPage == 0).help("Previous clipboard page")
                        Text("\(currentPage + 1)/\(count)").monospacedDigit().frame(minWidth: 22)
                        Button { page = min(count - 1, currentPage + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(currentPage + 1 >= count).help("Next clipboard page")
                    }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
                    Button { clearConfirmation = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .padding(.leading, 6).disabled(manager.regularHistory.isEmpty)
                        .help("Clear recent clipboard history")
                }
                if !enabled {
                    emptyState("Clipboard history is off", detail: "Enable Clipboard Manager in Settings → Clipboard.")
                } else if items.isEmpty {
                    emptyState(filter == .all ? "Your latest copies appear here" : "No \(filter.label.lowercased()) yet",
                               detail: filter == .all ? "Copy text, links, colors or images in any app. Click a card to copy it again." : "Choose All to see your other copied items.")
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(items[range])) { item in
                            card(item).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        ForEach(0..<max(0, columns - range.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .environment(\.colorScheme, .dark)
            .onChange(of: columns) { _, _ in page = 0 }
        }
        .onAppear { if enabled { manager.startMonitoring() } }
        .onChange(of: filter) { _, _ in page = 0 }
        .onChange(of: manager.clipboardHistory.map(\.id)) { _, _ in
            page = 0
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copiedID = nil }
        }
        .onChange(of: clearConfirmation) { _, visible in
            vm.setAutoCloseSuppression(visible, token: interactionToken)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: interactionToken) }
        .confirmationDialog("Clear recent clipboard history?", isPresented: $clearConfirmation) {
            Button("Clear History", role: .destructive) { manager.clearHistory(); page = 0 }
        }
    }

    private func filterButton(_ value: CompactClipboardKind) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 3) {
                if value != .all { Image(systemName: value.symbol).font(.system(size: 9)) }
                Text(value.label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(filter == value ? .black : .white.opacity(0.8))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(filter == value ? Color.white : Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter clipboard: \(value.label)")
        .accessibilityAddTraits(filter == value ? .isSelected : [])
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ item: ClipboardItem) -> some View {
        let type = kind(of: item)
        let color = cardColor(type)
        return Button {
            copyFailed = !manager.copyToClipboard(item)
            copiedID = copyFailed ? nil : item.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                preview(item, kind: type)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                HStack(spacing: 3) {
                    Text(type.footer).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
                    Spacer(minLength: 1)
                    Text(age(item.timestamp)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.black.opacity(0.3))
            }
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(copiedID == item.id ? Color.green : Color.white.opacity(0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Copy \(item.preview)")
        .accessibilityLabel("Copy \(type.footer.lowercased()): \(item.preview)")
    }

    @ViewBuilder
    private func preview(_ item: ClipboardItem, kind: CompactClipboardKind) -> some View {
        switch kind {
        case .image:
            ClipboardImagePreview(fileName: item.imageFileName)
        case .color:
            if let value = CompactClipboardPolicy.colorValue(item.stringData ?? "") {
                ZStack {
                    Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
                    Text((item.stringData ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle((value.red * 0.299 + value.green * 0.587 + value.blue * 0.114) > 0.6 ? .black : .white)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if kind != .code { Image(systemName: kind.symbol).font(.system(size: 13)).foregroundStyle(cardColor(kind)) }
                Text(String((item.stringData ?? item.preview).prefix(400)))
                    .font(.system(size: kind == .code ? 10 : 11, weight: .regular, design: kind == .code ? .monospaced : .default))
                    .foregroundStyle(kind == .code ? Color.green : Color.white.opacity(0.9))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(8)
        }
    }

    private func age(_ date: Date) -> String {
        let seconds = max(0, -date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    private func cardColor(_ kind: CompactClipboardKind) -> Color {
        switch kind {
        case .link: return .blue
        case .color: return .pink
        case .image: return .purple
        case .code: return .green
        case .text: return .cyan
        default: return .secondary
        }
    }
}

private struct ClipboardImagePreview: View {
    let fileName: String?
    @State private var image: NSImage?
    @State private var loading = false

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo").font(.system(size: 15))
                    Text(loading ? "Loading…" : "Image unavailable").font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .task(id: fileName) {
            image = nil
            guard let fileName else { loading = false; return }
            loading = true
            let thumbnail = await ClipboardThumbnailStore.shared.image(for: fileName)
            guard !Task.isCancelled else { return }
            image = thumbnail
            loading = false
        }
    }
}
