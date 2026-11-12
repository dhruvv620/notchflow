// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct CompactClipboardRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "CompactClipboardRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(CompactClipboardPolicy.kind(type: "text", text: "https://example.com/page") == .link, "Text URL not recognized")
        try require(CompactClipboardPolicy.kind(type: "text", text: "See https://example.com later") == .text, "Ordinary text became a link")
        try require(CompactClipboardPolicy.kind(type: "text", text: "#7C6CFF") == .color, "Hex color not recognized")
        try require(CompactClipboardPolicy.colorValue("bad") == nil, "A word became a hex color")
        try require(CompactClipboardPolicy.colorValue("#ff00")?.alpha == 0, "Short alpha hex was not expanded")
        try require(CompactClipboardPolicy.colorValue("#GGG") == nil, "Invalid hex accepted")
        try require(CompactClipboardPolicy.kind(type: "text", text: "git push origin main") == .code, "Command preview not classified as code")
        try require(CompactClipboardPolicy.kind(type: "rtf", text: "Can we move standup?") == .text, "Rich text lost Text filter")
        try require(CompactClipboardPolicy.kind(type: "image", text: nil) == .image, "Image not classified")
        try require(CompactClipboardPolicy.kind(type: "file", text: nil) == .file, "File not retained in All")
        try require(CompactClipboardPolicy.pageCount(itemCount: 20, pageSize: 5) == 4, "20 items should occupy four five-card pages")
        try require(CompactClipboardPolicy.range(page: 3, itemCount: 17, pageSize: 5) == (15..<17), "Partial final page incorrect")
        try require(CompactClipboardPolicy.range(page: 9, itemCount: 2, pageSize: 5) == (0..<2), "Filter change did not clamp page")
        try require(CompactClipboardPolicy.range(page: 2, itemCount: 0, pageSize: 5).isEmpty, "Empty page range invalid")
        try require(CompactClipboardPolicy.pageCount(itemCount: 0, pageSize: 0) == 1, "Empty/invalid pagination divided by zero")
        print("Compact clipboard classification and pagination checks passed")
    }
}
