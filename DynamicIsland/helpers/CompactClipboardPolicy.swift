// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Presentation classification only; the original pasteboard types/data remain unchanged.
enum CompactClipboardKind: String, CaseIterable, Identifiable {
    case all, link, color, image, code, text, file
    var id: String { rawValue }
    static let filters: [Self] = [.all, .link, .color, .image, .code, .text]

    var label: String {
        switch self {
        case .all: return "All"
        case .link: return "Links"
        case .color: return "Colors"
        case .image: return "Images"
        case .code: return "Code"
        case .text: return "Text"
        case .file: return "Files"
        }
    }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .link: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "text.alignleft"
        case .file: return "doc"
        }
    }
    var footer: String { self == .link ? "LINK" : rawValue.uppercased() }
}

struct ClipboardColorValue: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

enum CompactClipboardPolicy {
    static func colorValue(_ text: String) -> ClipboardColorValue? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Requiring # avoids treating everyday words such as "bad" as colors.
        guard text.hasPrefix("#") else { return nil }
        var hex = String(text.dropFirst())
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 6 { hex += "FF" }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return ClipboardColorValue(red: Double((value >> 24) & 255) / 255,
                                   green: Double((value >> 16) & 255) / 255,
                                   blue: Double((value >> 8) & 255) / 255,
                                   alpha: Double(value & 255) / 255)
    }

    static func kind(type: String, text: String?) -> CompactClipboardKind {
        if type == "image" { return .image }
        if type == "file" { return .file }
        if type == "url" { return .link }
        let text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if colorValue(text) != nil { return .color }
        if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           url.host != nil, !text.contains(where: \.isWhitespace) { return .link }
        if isCode(text) { return .code }
        return .text
    }

    private static func isCode(_ text: String) -> Bool {
        let prefixes = ["```", "git ", "npm ", "pnpm ", "yarn ", "brew ", "docker ", "kubectl ",
                        "cargo ", "swift ", "python ", "python3 ", "import ", "from ", "func ",
                        "struct ", "class ", "const ", "let ", "var ", "function ", "def ", "#!/"]
        if prefixes.contains(where: { text.hasPrefix($0) }) { return true }
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
        }
        return text.range(of: #"^</?[A-Za-z][A-Za-z0-9-]*(\s[^>]*|\s*)>"#, options: .regularExpression) != nil
    }

    static func pageCount(itemCount: Int, pageSize: Int) -> Int {
        let size = max(1, pageSize)
        return max(1, (max(0, itemCount) + size - 1) / size)
    }
    static func clampedPage(_ page: Int, itemCount: Int, pageSize: Int) -> Int {
        min(max(0, page), pageCount(itemCount: itemCount, pageSize: pageSize) - 1)
    }
    static func range(page: Int, itemCount: Int, pageSize: Int) -> Range<Int> {
        let size = max(1, pageSize)
        let start = clampedPage(page, itemCount: itemCount, pageSize: size) * size
        return start..<min(max(0, itemCount), start + size)
    }
}
