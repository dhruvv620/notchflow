// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// What a Glance panel shows.
enum GlancePanelKind: String, Codable, CaseIterable, Sendable {
    case web, pdf, calendar, reminders, clocks, promises, setups, stash, whatsapp

    /// Built-in panels exist once on a board; web pages and PDFs as many times as you add them.
    var isBuiltIn: Bool { self != .web && self != .pdf }

    var defaultTitle: String {
        switch self {
        case .web: return "Web page"
        case .pdf: return "PDF"
        case .calendar: return "Today"
        case .reminders: return "Reminders"
        case .clocks: return "World clocks"
        case .promises: return "Promises"
        case .setups: return "Window setups"
        case .stash: return "Window stash"
        case .whatsapp: return "WhatsApp"
        }
    }

    var symbol: String {
        switch self {
        case .web: return "globe"
        case .pdf: return "doc.richtext"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .clocks: return "clock"
        case .promises: return "hand.raised"
        case .setups: return "rectangle.3.group"
        case .stash: return "tray.full"
        case .whatsapp: return "message"
        }
    }

    /// Size in grid cells when added.
    var defaultSize: (width: Int, height: Int) {
        switch self {
        case .web, .pdf: return (3, 2)
        case .clocks, .stash: return (2, 1)
        default: return (2, 2)
        }
    }
}

/// A panel's place on the board's grid, in cells.
struct GlanceRect: Codable, Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func intersects(_ other: GlanceRect) -> Bool {
        x < other.x + other.width && other.x < x + width && y < other.y + other.height && other.y < y + height
    }
}

struct GlancePanel: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: GlancePanelKind
    var title: String
    /// A web page's address, or a PDF's path.
    var address = ""
    /// How often a web page reloads (when Glance opens and it's older than this).
    var refreshMinutes = 5
    /// Ask the site for its phone layout (fits small panels better).
    var mobileLayout = false
    /// World clocks: time zone identifiers ("Asia/Kolkata").
    var timeZones: [String] = []
    /// Off: kept in the list but not on the board.
    var isShown = true
    var frame: GlanceRect
}

/// One layout you can switch to ("Work", "Morning").
struct GlanceBoard: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var panels: [GlancePanel] = []
}

/// A ready-made arrangement: slots filled by the shown panels in order.
struct GlancePreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let slots: [GlanceRect]
}

/// Pure logic for Glance, the board you hold a key to see (Foundation only,
/// so Build.command can check it alone).
enum GlancePolicy {
    static let columns = 6
    static let rows = 4

    // MARK: Grid

    static func clamped(_ rect: GlanceRect) -> GlanceRect {
        let width = min(max(1, rect.width), columns)
        let height = min(max(1, rect.height), rows)
        return GlanceRect(x: min(max(0, rect.x), columns - width), y: min(max(0, rect.y), rows - height),
                          width: width, height: height)
    }

    /// Whether a spot is inside the grid and clear of the other shown panels.
    static func isFree(_ rect: GlanceRect, on board: GlanceBoard, ignoring id: UUID? = nil) -> Bool {
        guard rect.x >= 0, rect.y >= 0, rect.x + rect.width <= columns, rect.y + rect.height <= rows else { return false }
        return !board.panels.contains { $0.isShown && $0.id != id && $0.frame.intersects(rect) }
    }

    /// The first clear spot for a panel of this size (row by row), trying
    /// smaller sizes when it doesn't fit, down to one cell.
    static func freeSpot(width: Int, height: Int, on board: GlanceBoard, ignoring id: UUID? = nil) -> GlanceRect? {
        var sizes: [(Int, Int)] = [(width, height)]
        if height > 1 { sizes.append((width, height - 1)) }
        if width > 1 { sizes.append((width - 1, height)) }
        sizes += [(2, 1), (1, 1)]
        for (w, h) in sizes where w <= columns && h <= rows {
            for y in 0...(rows - h) {
                for x in 0...(columns - w) {
                    let rect = GlanceRect(x: x, y: y, width: w, height: h)
                    if isFree(rect, on: board, ignoring: id) { return rect }
                }
            }
        }
        return nil
    }

    // MARK: Editing

    /// Adds a panel where there's room (hidden when the board is full).
    static func adding(_ kind: GlancePanelKind, title: String? = nil, address: String = "", to board: GlanceBoard) -> GlanceBoard {
        var board = board
        let size = kind.defaultSize
        let spot = freeSpot(width: size.width, height: size.height, on: board)
        var panel = GlancePanel(kind: kind, title: title ?? kind.defaultTitle, address: address, isShown: spot != nil,
                                frame: spot ?? GlanceRect(x: 0, y: 0, width: size.width, height: size.height))
        if kind == .clocks { panel.timeZones = defaultTimeZones }
        board.panels.append(panel)
        return board
    }

    /// Shows or hides a panel; shown again, it goes where there's room.
    static func setting(_ id: UUID, shown: Bool, on board: GlanceBoard) -> GlanceBoard {
        var board = board
        guard let index = board.panels.firstIndex(where: { $0.id == id }) else { return board }
        if shown {
            let panel = board.panels[index]
            if isFree(panel.frame, on: board, ignoring: id) {
                board.panels[index].isShown = true
            } else if let spot = freeSpot(width: panel.frame.width, height: panel.frame.height, on: board, ignoring: id) {
                board.panels[index].frame = spot
                board.panels[index].isShown = true
            }
        } else {
            board.panels[index].isShown = false
        }
        return board
    }

    /// Drops a panel at a cell. Onto empty space it moves there; onto
    /// another panel, the two swap places (each keeping its size where it fits).
    static func moving(_ id: UUID, toX x: Int, y: Int, on board: GlanceBoard) -> GlanceBoard {
        var board = board
        guard let index = board.panels.firstIndex(where: { $0.id == id }) else { return board }
        let original = board.panels[index].frame
        let target = clamped(GlanceRect(x: x, y: y, width: original.width, height: original.height))
        guard target != original else { return board }
        if isFree(target, on: board, ignoring: id) {
            board.panels[index].frame = target
            return board
        }
        let hit = board.panels.indices.filter { board.panels[$0].isShown && $0 != index && board.panels[$0].frame.intersects(target) }
        guard hit.count == 1 else { return board }
        let other = hit[0]
        var swapped = board
        swapped.panels[index].frame = clamped(GlanceRect(x: board.panels[other].frame.x, y: board.panels[other].frame.y,
                                                         width: original.width, height: original.height))
        swapped.panels[other].frame = clamped(GlanceRect(x: original.x, y: original.y,
                                                         width: board.panels[other].frame.width, height: board.panels[other].frame.height))
        // Only when they don't end up on top of each other or of a third panel.
        let shown = swapped.panels.filter(\.isShown)
        for (i, a) in shown.enumerated() {
            for b in shown.dropFirst(i + 1) where a.frame.intersects(b.frame) { return board }
        }
        return swapped
    }

    /// Resizes a panel when the new size is clear.
    static func resizing(_ id: UUID, width: Int, height: Int, on board: GlanceBoard) -> GlanceBoard {
        var board = board
        guard let index = board.panels.firstIndex(where: { $0.id == id }) else { return board }
        let frame = board.panels[index].frame
        let rect = GlanceRect(x: frame.x, y: frame.y, width: max(1, min(width, columns - frame.x)), height: max(1, min(height, rows - frame.y)))
        if isFree(rect, on: board, ignoring: id) { board.panels[index].frame = rect }
        return board
    }

    static func removing(_ id: UUID, from board: GlanceBoard) -> GlanceBoard {
        var board = board
        board.panels.removeAll { $0.id == id }
        return board
    }

    /// The cell under a point of the editor (0...1 across and down).
    static func cell(atFractionX fx: Double, y fy: Double) -> (x: Int, y: Int) {
        (min(columns - 1, max(0, Int((fx * Double(columns)).rounded(.down)))),
         min(rows - 1, max(0, Int((fy * Double(rows)).rounded(.down)))))
    }

    // MARK: Presets

    static let presets: [GlancePreset] = [
        GlancePreset(id: "focus", name: "Focus", slots: [
            GlanceRect(x: 0, y: 0, width: 4, height: 4), GlanceRect(x: 4, y: 0, width: 2, height: 2),
            GlanceRect(x: 4, y: 2, width: 2, height: 2)]),
        GlancePreset(id: "dashboard", name: "Dashboard", slots: [
            GlanceRect(x: 0, y: 0, width: 2, height: 2), GlanceRect(x: 2, y: 0, width: 2, height: 2),
            GlanceRect(x: 4, y: 0, width: 2, height: 2), GlanceRect(x: 0, y: 2, width: 2, height: 2),
            GlanceRect(x: 2, y: 2, width: 2, height: 2), GlanceRect(x: 4, y: 2, width: 2, height: 2)]),
        GlancePreset(id: "halves", name: "Two halves", slots: [
            GlanceRect(x: 0, y: 0, width: 3, height: 4), GlanceRect(x: 3, y: 0, width: 3, height: 4)]),
        GlancePreset(id: "wide", name: "Wide on top", slots: [
            GlanceRect(x: 0, y: 0, width: 6, height: 2), GlanceRect(x: 0, y: 2, width: 2, height: 2),
            GlanceRect(x: 2, y: 2, width: 2, height: 2), GlanceRect(x: 4, y: 2, width: 2, height: 2)]),
        GlancePreset(id: "sidebar", name: "Sidebar", slots: [
            GlanceRect(x: 0, y: 0, width: 4, height: 4), GlanceRect(x: 4, y: 0, width: 2, height: 1),
            GlanceRect(x: 4, y: 1, width: 2, height: 1), GlanceRect(x: 4, y: 2, width: 2, height: 1),
            GlanceRect(x: 4, y: 3, width: 2, height: 1)]),
    ]

    /// Arranges the shown panels into a preset's slots, in their order; any
    /// beyond the slots go where there's room, or are hidden.
    static func applying(_ preset: GlancePreset, to board: GlanceBoard) -> GlanceBoard {
        var board = board
        let shown = board.panels.indices.filter { board.panels[$0].isShown }
        for index in shown { board.panels[index].isShown = false }
        for (slot, index) in zip(preset.slots, shown) {
            board.panels[index].frame = slot
            board.panels[index].isShown = true
        }
        for index in shown.dropFirst(preset.slots.count) {
            board = setting(board.panels[index].id, shown: true, on: board)
        }
        return board
    }

    // MARK: Boards

    static let defaultTimeZones = ["America/New_York", "Europe/London", "Asia/Tokyo"]

    /// The board Glance starts with: today down the left, reminders and
    /// promises in the middle, clocks down the right.
    static func starterBoard() -> GlanceBoard {
        var board = GlanceBoard(name: "My Glance")
        for kind in [GlancePanelKind.calendar, .reminders, .promises, .clocks] { board = adding(kind, to: board) }
        let frames = [GlanceRect(x: 0, y: 0, width: 2, height: 4), GlanceRect(x: 2, y: 0, width: 2, height: 2),
                      GlanceRect(x: 2, y: 2, width: 2, height: 2), GlanceRect(x: 4, y: 0, width: 2, height: 4)]
        for (index, frame) in frames.enumerated() {
            board.panels[index].frame = frame
            board.panels[index].isShown = true
        }
        return board
    }

    /// A copy under a new name (new ids, same panels).
    static func duplicate(_ board: GlanceBoard, name: String) -> GlanceBoard {
        var copy = board
        copy.id = UUID()
        copy.name = name
        copy.panels = board.panels.map { var panel = $0; panel.id = UUID(); return panel }
        return copy
    }

    static func decodeBoards(_ data: Data) -> [GlanceBoard] {
        (try? JSONDecoder().decode([GlanceBoard].self, from: data)) ?? []
    }

    static func encodeBoards(_ boards: [GlanceBoard]) -> Data {
        (try? JSONEncoder().encode(boards)) ?? Data()
    }

    // MARK: Web pages

    /// A typed address as a URL ("github.com" → https://github.com).
    static func webURL(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.contains(".") == true || url.host == "localhost" else { return nil }
        return url
    }

    /// Whether a web page is due a reload when Glance opens.
    static func needsReload(loadedAt: Date?, refreshMinutes: Int, now: Date) -> Bool {
        guard let loadedAt else { return true }
        return now.timeIntervalSince(loadedAt) >= Double(max(1, refreshMinutes)) * 60
    }

    /// Ad and tracker hosts that web panels don't load.
    static let blockedHosts = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "amazon-adsystem.com", "taboola.com", "outbrain.com", "criteo.com", "adnxs.com", "rubiconproject.com",
        "pubmatic.com", "scorecardresearch.com", "moatads.com", "quantserve.com", "adsrvr.org",
    ]

    /// Cookie-consent banners hidden in web panels.
    static let cookieBannerSelectors = [
        "#onetrust-banner-sdk", "#onetrust-consent-sdk", "#CybotCookiebotDialog", ".cc-window", ".cookie-banner",
        "#cookie-banner", ".cookie-consent", "#cookie-consent", ".fc-consent-root", "#usercentrics-root",
        ".qc-cmp2-container", "#didomi-host", ".truste_box_overlay", "#truste-consent-track",
    ]

    /// WebKit content rules: block the ad hosts and hide the cookie banners.
    static func contentRules() -> String {
        var rules: [[String: Any]] = blockedHosts.map { host in
            ["trigger": ["url-filter": "^https?://([^/]*\\.)?" + NSRegularExpression.escapedPattern(for: host) + "[:/]",
                         "load-type": ["third-party"]],
             "action": ["type": "block"]]
        }
        rules.append(["trigger": ["url-filter": ".*"],
                      "action": ["type": "css-display-none", "selector": cookieBannerSelectors.joined(separator: ", ")]])
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Hold or tap

    /// Released this soon after pressing, the shortcut was a tap: the board stays open.
    static let tapLimit: TimeInterval = 0.35

    static func isTap(heldFor seconds: TimeInterval) -> Bool { seconds < tapLimit }
}
