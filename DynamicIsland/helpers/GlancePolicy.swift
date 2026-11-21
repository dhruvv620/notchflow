// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// What a Glance panel shows.
enum GlancePanelKind: String, Codable, CaseIterable, Sendable {
    case web, pdf, html, window, calendar, reminders, clocks, stocks, weather, nowPlaying, promises, setups, stash, whatsapp

    /// Built-in panels exist once on a board; web pages, files, app windows
    /// and weather (one per city) as many times as you add them.
    var isBuiltIn: Bool { ![.web, .pdf, .html, .window, .weather].contains(self) }

    var defaultTitle: String {
        switch self {
        case .web: return "Web page"
        case .pdf: return "PDF"
        case .html: return "Widget"
        case .window: return "App window"
        case .calendar: return "Today"
        case .reminders: return "Reminders"
        case .clocks: return "World clocks"
        case .stocks: return "Stocks"
        case .weather: return "Weather"
        case .nowPlaying: return "Now playing"
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
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .window: return "macwindow"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .clocks: return "clock"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .weather: return "cloud.sun"
        case .nowPlaying: return "music.note"
        case .promises: return "hand.raised"
        case .setups: return "rectangle.3.group"
        case .stash: return "tray.full"
        case .whatsapp: return "message"
        }
    }

    /// Size in grid cells when added.
    var defaultSize: (width: Int, height: Int) {
        let unit = GlancePolicy.unit
        switch self {
        case .web, .pdf, .html, .window: return (6 * unit, 4 * unit)
        case .clocks, .stash: return (5 * unit, 2 * unit)
        case .nowPlaying: return (4 * unit, 6 * unit)
        case .weather: return (4 * unit, 3 * unit)
        default: return (4 * unit, 4 * unit)
        }
    }

    /// The choices of what a panel shows (calendar: day or week; reminders: which ones).
    var views: [(id: String, title: String)] {
        switch self {
        case .calendar: return [("day", "Day"), ("week", "Week")]
        case .reminders: return [("all", "All"), ("today", "Today"), ("scheduled", "Scheduled"), ("overdue", "Overdue")]
        default: return []
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

    /// Cells shared with another rect.
    func overlap(_ other: GlanceRect) -> Int {
        let w = min(x + width, other.x + other.width) - max(x, other.x)
        let h = min(y + height, other.y + other.height) - max(y, other.y)
        return w > 0 && h > 0 ? w * h : 0
    }

    var area: Int { width * height }

    func scaled(by factor: Int) -> GlanceRect {
        GlanceRect(x: x * factor, y: y * factor, width: width * factor, height: height * factor)
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
    /// Stocks: ticker symbols ("AAPL", "RELIANCE.NS").
    var symbols: [String] = []
    /// App window: the app (bundle id) and the window's title when picked.
    var windowApp = ""
    var windowTitle = ""
    /// What it shows, for kinds with a choice (calendar "day"/"week", reminders "today"…).
    var view = ""
    /// Web page: parts of the page you hid (CSS selectors).
    var hiddenSelectors: [String] = []
    /// Off: kept in the list but not on the board.
    var isShown = true
    var frame: GlanceRect

    init(id: UUID = UUID(), kind: GlancePanelKind, title: String, address: String = "", refreshMinutes: Int = 5,
         mobileLayout: Bool = false, timeZones: [String] = [], symbols: [String] = [], windowApp: String = "",
         windowTitle: String = "", view: String = "", hiddenSelectors: [String] = [], isShown: Bool = true, frame: GlanceRect) {
        self.id = id
        self.kind = kind
        self.title = title
        self.address = address
        self.refreshMinutes = refreshMinutes
        self.mobileLayout = mobileLayout
        self.timeZones = timeZones
        self.symbols = symbols
        self.windowApp = windowApp
        self.windowTitle = windowTitle
        self.view = view
        self.hiddenSelectors = hiddenSelectors
        self.isShown = isShown
        self.frame = frame
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, address, refreshMinutes, mobileLayout, timeZones, symbols, windowApp, windowTitle, view, hiddenSelectors
        case isShown, frame
    }

    /// Reads boards saved by any version: options added later take their defaults.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(GlancePanelKind.self, forKey: .kind)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? kind.defaultTitle
        address = try values.decodeIfPresent(String.self, forKey: .address) ?? ""
        refreshMinutes = try values.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5
        mobileLayout = try values.decodeIfPresent(Bool.self, forKey: .mobileLayout) ?? false
        timeZones = try values.decodeIfPresent([String].self, forKey: .timeZones) ?? []
        symbols = try values.decodeIfPresent([String].self, forKey: .symbols) ?? []
        windowApp = try values.decodeIfPresent(String.self, forKey: .windowApp) ?? ""
        windowTitle = try values.decodeIfPresent(String.self, forKey: .windowTitle) ?? ""
        view = try values.decodeIfPresent(String.self, forKey: .view) ?? ""
        hiddenSelectors = try values.decodeIfPresent([String].self, forKey: .hiddenSelectors) ?? []
        isShown = try values.decodeIfPresent(Bool.self, forKey: .isShown) ?? true
        frame = try values.decode(GlanceRect.self, forKey: .frame)
    }
}

/// One layout you can switch to ("Work", "Morning").
struct GlanceBoard: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var panels: [GlancePanel] = []
    /// Columns of the grid its panels were placed on (boards from before the
    /// finer grid had 6; they're scaled up when read).
    var grid = GlancePolicy.columns

    init(id: UUID = UUID(), name: String, panels: [GlancePanel] = []) {
        self.id = id
        self.name = name
        self.panels = panels
    }

    private enum CodingKeys: String, CodingKey { case id, name, panels, grid }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Glance"
        panels = try values.decodeIfPresent([GlancePanel].self, forKey: .panels) ?? []
        let saved = try values.decodeIfPresent(Int.self, forKey: .grid) ?? 6
        if saved > 0, saved < GlancePolicy.columns, GlancePolicy.columns % saved == 0 {
            let factor = GlancePolicy.columns / saved
            for index in panels.indices { panels[index].frame = panels[index].frame.scaled(by: factor) }
        }
        grid = GlancePolicy.columns
    }
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
    /// The grid is fine (24 × 16) so panels can go almost anywhere; presets
    /// and default sizes are in steps of `unit` cells.
    static let unit = 4
    static let columns = 6 * unit
    static let rows = 4 * unit

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
        sizes += [(width / 2, height / 2), (2 * unit, unit), (unit, unit), (1, 1)]
        for (w, h) in sizes where w >= 1 && h >= 1 && w <= columns && h <= rows {
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
    static func adding(_ kind: GlancePanelKind, title: String? = nil, address: String = "", to board: GlanceBoard,
                       near cell: (x: Int, y: Int)? = nil) -> GlanceBoard {
        var board = board
        let size = kind.defaultSize
        var spot: GlanceRect?
        if let cell {
            // Centred on where you pointed, or the clear spot closest to it.
            let wanted = clamped(GlanceRect(x: cell.x - size.width / 2, y: cell.y - size.height / 2, width: size.width, height: size.height))
            spot = isFree(wanted, on: board) ? wanted : nearestFreeSpot(to: wanted, on: board, ignoring: nil, within: max(columns, rows))
        }
        spot = spot ?? freeSpot(width: size.width, height: size.height, on: board)
        var panel = GlancePanel(kind: kind, title: title ?? kind.defaultTitle, address: address, isShown: spot != nil,
                                frame: spot ?? GlanceRect(x: 0, y: 0, width: size.width, height: size.height))
        if kind == .clocks { panel.timeZones = defaultTimeZones }
        if kind == .stocks { panel.symbols = defaultSymbols }
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

    /// Drops a panel at a cell. Onto empty space it moves there; mostly
    /// onto one other panel, the two swap places; partly onto others, it
    /// goes to the nearest clear spot close by.
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
        if hit.count == 1 {
            let other = hit[0]
            let shared = board.panels[other].frame.overlap(target)
            if shared * 2 >= min(target.area, board.panels[other].frame.area) {
                var swapped = board
                swapped.panels[index].frame = clamped(GlanceRect(x: board.panels[other].frame.x, y: board.panels[other].frame.y,
                                                                 width: original.width, height: original.height))
                swapped.panels[other].frame = clamped(GlanceRect(x: original.x, y: original.y,
                                                                 width: board.panels[other].frame.width, height: board.panels[other].frame.height))
                if !hasOverlaps(swapped) { return swapped }
            }
        }
        if let near = nearestFreeSpot(to: target, on: board, ignoring: id, within: 2 * unit) {
            board.panels[index].frame = near
        }
        return board
    }

    /// The clear spot of the same size closest to `target`, within a distance (cells).
    static func nearestFreeSpot(to target: GlanceRect, on board: GlanceBoard, ignoring id: UUID?, within distance: Int) -> GlanceRect? {
        var best: (GlanceRect, Int)?
        for dy in -distance...distance {
            for dx in -distance...distance {
                let rect = GlanceRect(x: target.x + dx, y: target.y + dy, width: target.width, height: target.height)
                let cost = abs(dx) + abs(dy)
                guard cost <= distance, best.map({ cost < $0.1 }) ?? true, isFree(rect, on: board, ignoring: id) else { continue }
                best = (rect, cost)
            }
        }
        return best?.0
    }

    static func hasOverlaps(_ board: GlanceBoard) -> Bool {
        let shown = board.panels.filter(\.isShown)
        for (i, a) in shown.enumerated() {
            for b in shown.dropFirst(i + 1) where a.frame.intersects(b.frame) { return true }
        }
        return false
    }

    /// Resizes a panel; where the new size runs into another panel, it
    /// grows as far as there's room.
    static func resizing(_ id: UUID, width: Int, height: Int, on board: GlanceBoard) -> GlanceBoard {
        var board = board
        guard let index = board.panels.firstIndex(where: { $0.id == id }) else { return board }
        let frame = board.panels[index].frame
        let wanted = (w: max(1, min(width, columns - frame.x)), h: max(1, min(height, rows - frame.y)))
        var best: GlanceRect?
        for w in stride(from: wanted.w, through: 1, by: -1) {
            for h in stride(from: wanted.h, through: 1, by: -1) {
                let rect = GlanceRect(x: frame.x, y: frame.y, width: w, height: h)
                if (best.map { rect.area > $0.area } ?? true), isFree(rect, on: board, ignoring: id) { best = rect }
            }
        }
        if let best { board.panels[index].frame = best }
        return board
    }

    /// Moves and resizes in one go (dragging a top or left edge): the new
    /// rect when it's clear, else unchanged.
    static func reframing(_ id: UUID, to rect: GlanceRect, on board: GlanceBoard) -> GlanceBoard {
        var board = board
        guard let index = board.panels.firstIndex(where: { $0.id == id }) else { return board }
        let target = clamped(rect)
        if isFree(target, on: board, ignoring: id) { board.panels[index].frame = target }
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

    static let presets: [GlancePreset] = coarsePresets.map { preset in
        GlancePreset(id: preset.id, name: preset.name, slots: preset.slots.map { $0.scaled(by: unit) })
    }

    /// The presets on a 6 × 4 grid.
    private static let coarsePresets: [GlancePreset] = [
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
                      GlanceRect(x: 2, y: 2, width: 2, height: 2), GlanceRect(x: 4, y: 0, width: 2, height: 4)].map { $0.scaled(by: unit) }
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

    /// Saved boards; a panel of a kind this version doesn't know is skipped, not the whole board.
    static func decodeBoards(_ data: Data) -> [GlanceBoard] {
        if let boards = try? JSONDecoder().decode([GlanceBoard].self, from: data) { return boards }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { object in
            var object = object
            let panels = (object["panels"] as? [[String: Any]]) ?? []
            object["panels"] = panels.filter { panel in
                guard let piece = try? JSONSerialization.data(withJSONObject: panel) else { return false }
                return (try? JSONDecoder().decode(GlancePanel.self, from: piece)) != nil
            }
            guard let cleaned = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? JSONDecoder().decode(GlanceBoard.self, from: cleaned)
        }
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
        // Trackers
        "google-analytics.com", "googletagmanager.com", "connect.facebook.net", "hotjar.com", "segment.io",
        "segment.com", "mixpanel.com", "amplitude.com", "clarity.ms", "fullstory.com", "newrelic.com", "branch.io",
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

    // MARK: Displays

    /// Which board each display shows when Glance opens: the display with
    /// the pointer shows the board you gave it (else the selected one);
    /// other displays only when you gave them a board, and not one already
    /// showing (a web page or window can be in only one place).
    /// With "same on all displays", every display shows the selected board.
    static func boardsToShow(displays: [String], pointer: String?, assignments: [String: UUID],
                             selected: UUID, boards: Set<UUID>, sameOnAll: Bool = false) -> [String: UUID] {
        if sameOnAll { return Dictionary(uniqueKeysWithValues: displays.map { ($0, selected) }) }
        func valid(_ id: UUID?) -> UUID? { id.flatMap { boards.contains($0) ? $0 : nil } }
        var result: [String: UUID] = [:]
        var used = Set<UUID>()
        if let pointer, displays.contains(pointer) {
            let id = valid(assignments[pointer]) ?? selected
            result[pointer] = id
            used.insert(id)
        }
        for display in displays where display != pointer {
            if let id = valid(assignments[display]), used.insert(id).inserted { result[display] = id }
        }
        return result
    }

    // MARK: Stocks

    struct StockQuote: Equatable, Sendable {
        let symbol: String
        let name: String
        let price: Double
        let previousClose: Double?
        let currency: String?
        /// Today's prices, oldest first, for the little chart.
        let points: [Double]

        var change: Double? { previousClose.map { price - $0 } }
        var changePercent: Double? {
            guard let previousClose, previousClose != 0 else { return nil }
            return (price - previousClose) / previousClose * 100
        }
    }

    static let defaultSymbols = ["AAPL", "^NSEI", "BTC-USD"]

    /// Symbols typed in a list ("aapl, reliance.ns  TSLA").
    static func symbols(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty && $0.count <= 20 && $0.allSatisfy { $0.isLetter || $0.isNumber || ".^=-_".contains($0) } }
            .filter { seen.insert($0).inserted }
    }

    /// Yahoo Finance's public chart data for today (no account; NSE stocks end in .NS, BSE in .BO).
    static func stockURL(_ symbol: String) -> URL? {
        guard let clean = symbols(from: symbol).first,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-_"))) else { return nil }
        return URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=15m")
    }

    static func quote(from data: Data) -> StockQuote? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = object["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let symbol = meta["symbol"] as? String,
              let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue else { return nil }
        let previous = (meta["chartPreviousClose"] as? NSNumber)?.doubleValue ?? (meta["previousClose"] as? NSNumber)?.doubleValue
        let name = (meta["shortName"] as? String) ?? (meta["longName"] as? String) ?? symbol
        let quote = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first
        let points = ((quote?["close"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        return StockQuote(symbol: symbol, name: name, price: price, previousClose: previous,
                          currency: meta["currency"] as? String, points: points)
    }

    // MARK: Pages in your own browser

    /// A browser Glance can show pages in, signed in as you: Chromium
    /// browsers open a page as a borderless "app" window; Safari as a normal window.
    struct Browser: Equatable, Sendable {
        let name: String
        let bundleID: String
        let isChromium: Bool
    }

    static let browsers: [Browser] = [
        Browser(name: "Chrome Beta", bundleID: "com.google.Chrome.beta", isChromium: true),
        Browser(name: "Chrome", bundleID: "com.google.Chrome", isChromium: true),
        Browser(name: "Chrome Canary", bundleID: "com.google.Chrome.canary", isChromium: true),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isChromium: true),
        Browser(name: "Brave", bundleID: "com.brave.Browser", isChromium: true),
        Browser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", isChromium: true),
        Browser(name: "Safari", bundleID: "com.apple.Safari", isChromium: false),
    ]

    /// The browser for web pages: "builtIn" (NotchFlow's own pages), a
    /// browser's bundle id, or "auto" (the first installed, Chrome Beta first).
    static func browser(setting: String, installed: Set<String>) -> Browser? {
        if setting == "builtIn" { return nil }
        if let chosen = browsers.first(where: { $0.bundleID == setting }), installed.contains(chosen.bundleID) { return chosen }
        return browsers.first { installed.contains($0.bundleID) }
    }

    /// Arguments that open a page as an app window in a Chromium browser (your profile, no tabs or address bar).
    static func appWindowArguments(url: URL) -> [String] {
        ["--app=" + url.absoluteString]
    }

    /// AppleScript that opens a page in a new Safari window.
    static func safariWindowScript(url: URL) -> String {
        let escaped = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application id \"com.apple.Safari\" to make new document with properties {URL:\"\(escaped)\"}"
    }

    /// AppleScript listing a browser's open tabs as "title<TAB>url" lines.
    static func openTabsScript(_ browser: Browser) -> String {
        let titleProperty = browser.isChromium ? "title" : "name"
        return """
        set out to ""
        tell application id "\(browser.bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (\(titleProperty) of t) & tab & (URL of t) & linefeed
                end repeat
            end repeat
        end tell
        return out
        """
    }

    /// The open tabs from that script's answer (web pages only, no repeats).
    static func openTabs(from text: String) -> [(title: String, url: String)] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { line -> (title: String, url: String)? in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let url = webURL(parts[1]), seen.insert(url.absoluteString).inserted else { return nil }
            let title = parts[0].trimmingCharacters(in: .whitespaces)
            return (title.isEmpty ? (url.host ?? parts[1]) : title, parts[1])
        }
    }

    /// Where a panel is on a display, in Accessibility coordinates (top left
    /// of the main display is 0,0, y grows down): where a real window goes.
    /// `area` is the board's panel area within the display (top-left origin).
    static func screenRect(for frame: GlanceRect, area: CGRect, gap: Double, display: CGRect, mainDisplayHeight: Double) -> CGRect {
        let cellWidth = area.width / Double(columns)
        let cellHeight = area.height / Double(rows)
        let x = area.minX + Double(frame.x) * cellWidth + gap / 2
        let y = area.minY + Double(frame.y) * cellHeight + gap / 2
        return CGRect(x: display.minX + x, y: mainDisplayHeight - display.maxY + y,
                      width: Double(frame.width) * cellWidth - gap, height: Double(frame.height) * cellHeight - gap)
    }

    /// Where a browser window waits between glances: just past the bottom
    /// right corner of the displays (macOS keeps a sliver on screen), in
    /// Accessibility coordinates. `displays` are in Accessibility coordinates too.
    static func parkingOrigin(displays: [CGRect]) -> CGPoint {
        guard let maxX = displays.map(\.maxX).max(), let maxY = displays.map(\.maxY).max() else { return CGPoint(x: 10_000, y: 10_000) }
        return CGPoint(x: maxX - 1, y: maxY - 1)
    }

    // MARK: Live windows

    struct WindowCandidate: Equatable, Sendable {
        let bundleID: String
        let title: String
        let area: Double
    }

    /// The window an App window panel shows: the one with the title you
    /// picked, else the one whose title shares most of its words (a
    /// browser's title follows its page, counts change), else that app's
    /// biggest window.
    static func pickWindow(_ candidates: [WindowCandidate], app: String, title: String) -> Int? {
        let mine = candidates.indices.filter { candidates[$0].bundleID == app && candidates[$0].area >= 10_000 }
        guard !mine.isEmpty else { return nil }
        if !title.isEmpty {
            if let exact = mine.first(where: { candidates[$0].title == title }) { return exact }
            let wanted = words(title)
            let scored = mine.map { index -> (Int, Double) in
                let found = words(candidates[index].title)
                let union = wanted.union(found)
                return (index, union.isEmpty ? 0 : Double(wanted.intersection(found).count) / Double(union.count))
            }
            if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 { return best.0 }
        }
        return mine.max { candidates[$0].area < candidates[$1].area }
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 })
    }

    // MARK: Opening it

    /// How the board opens.
    enum Mode: String, CaseIterable, Sendable {
        case holdOrTap, hold, toggle

        var title: String {
            switch self {
            case .holdOrTap: return "Hold to peek, tap to keep open"
            case .hold: return "Hold to show, release to hide"
            case .toggle: return "Press to show, press again to hide"
            }
        }
    }

    /// What opens it: the shortcut, or one modifier key on its own.
    enum Trigger: String, CaseIterable, Sendable {
        case shortcut, fn, shift, leftShift, rightShift, leftCommand, rightCommand, leftOption, rightOption, leftControl, rightControl

        var title: String {
            switch self {
            case .shortcut: return "Keyboard shortcut"
            case .fn: return "fn (Globe)"
            case .shift: return "Shift (either)"
            case .leftShift: return "Left Shift"
            case .rightShift: return "Right Shift"
            case .leftCommand: return "Left Command"
            case .rightCommand: return "Right Command"
            case .leftOption: return "Left Option"
            case .rightOption: return "Right Option"
            case .leftControl: return "Left Control"
            case .rightControl: return "Right Control"
            }
        }

        /// The keys (virtual key codes) that count as this trigger.
        var keyCodes: Set<UInt16> {
            switch self {
            case .shortcut: return []
            case .fn: return [63]
            case .shift: return [56, 60]
            case .leftShift: return [56]
            case .rightShift: return [60]
            case .leftCommand: return [55]
            case .rightCommand: return [54]
            case .leftOption: return [58]
            case .rightOption: return [61]
            case .leftControl: return [59]
            case .rightControl: return [62]
            }
        }

        /// The trigger for a modifier key pressed on its own (when recording one).
        static func forKeyCode(_ keyCode: UInt16) -> Trigger? {
            [.fn, .leftShift, .rightShift, .leftCommand, .rightCommand, .leftOption, .rightOption, .leftControl, .rightControl]
                .first { $0.keyCodes == [keyCode] }
        }
    }

    /// Whether the modifier key that just changed is now down, from the
    /// event's flags (which tell left and right apart).
    static func isModifierDown(keyCode: UInt16, flags: UInt) -> Bool {
        let masks: [UInt16: UInt] = [56: 0x2, 60: 0x4, 55: 0x8, 54: 0x10, 58: 0x20, 61: 0x40, 59: 0x1, 62: 0x2000, 63: 0x800000]
        guard let mask = masks[keyCode] else { return false }
        return flags & mask != 0
    }

    /// A trigger key, telling a hold or tap apart from typing: Shift held
    /// for a capital letter never opens the board, because another key comes
    /// before the hold time is up.
    struct ModifierGesture: Sendable {
        enum Action: Equatable, Sendable {
            case none, show, hide, toggle
            /// Keep it open (showing it first if needed).
            case pin
        }

        /// Held this long, on its own, it opens the board.
        static let holdDelay: TimeInterval = 0.22
        /// Released within this, on its own, it was a tap.
        static let tapLimit: TimeInterval = 0.4

        var mode: Mode
        private(set) var downAt: Date?
        private(set) var interrupted = false
        private(set) var pinnedAtDown = false

        init(mode: Mode) { self.mode = mode }

        mutating func triggerDown(at date: Date, pinned: Bool = false) {
            downAt = date
            interrupted = false
            pinnedAtDown = pinned
        }

        /// Another key or a click while the trigger is down: it's a shortcut or typing, not a glance.
        mutating func otherInput(showing: Bool) {
            if downAt != nil && !showing { interrupted = true }
        }

        /// Checked a moment after the trigger went down.
        func holdElapsed(at date: Date, showing: Bool) -> Action {
            guard mode != .toggle, !showing, let downAt, !interrupted,
                  date.timeIntervalSince(downAt) >= Self.holdDelay else { return .none }
            return .show
        }

        mutating func triggerUp(at date: Date, showing: Bool) -> Action {
            defer { downAt = nil; interrupted = false; pinnedAtDown = false }
            guard let downAt else { return .none }
            let tap = !interrupted && date.timeIntervalSince(downAt) < Self.tapLimit
            switch mode {
            case .hold:
                return showing ? .hide : .none
            case .toggle:
                return tap ? .toggle : .none
            case .holdOrTap:
                if tap { return pinnedAtDown ? .hide : .pin }
                return showing ? .hide : .none
            }
        }
    }

    /// How the screen behind the panels looks.
    enum Backdrop: String, CaseIterable, Sendable {
        case clear, dim, blur

        var title: String {
            switch self {
            case .clear: return "Clear"
            case .dim: return "Dimmed"
            case .blur: return "Blurred"
            }
        }
    }

    // MARK: Reminders and calendar views

    /// Whether a reminder belongs in a Reminders panel's view.
    static func reminderMatches(view: String, due: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        switch view {
        case "today": return due.map { $0 >= today && $0 < tomorrow } ?? false
        case "scheduled": return due != nil
        case "overdue": return due.map { $0 < today } ?? false
        default: return true
        }
    }

    /// The days a week view shows: today and the six after it.
    static func weekDays(from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    // MARK: Weather

    struct WeatherPlace: Equatable, Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    struct WeatherDay: Equatable, Sendable {
        let date: String
        let code: Int
        let high: Double
        let low: Double
    }

    struct WeatherReport: Equatable, Sendable {
        let temperature: Double
        let code: Int
        let isDay: Bool
        let unit: String
        let days: [WeatherDay]
    }

    /// Open-Meteo's free geocoding (no account): a city name to a place.
    static func geocodeURL(_ city: String) -> URL? {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [URLQueryItem(name: "name", value: trimmed), URLQueryItem(name: "count", value: "1"),
                                  URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        return components?.url
    }

    static func place(from data: Data) -> WeatherPlace? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (object["results"] as? [[String: Any]])?.first,
              let name = first["name"] as? String,
              let latitude = (first["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (first["longitude"] as? NSNumber)?.doubleValue else { return nil }
        return WeatherPlace(name: name, latitude: latitude, longitude: longitude)
    }

    /// Open-Meteo's free forecast (no account): now and the next days.
    static func forecastURL(_ place: WeatherPlace, fahrenheit: Bool) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        var items = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
        ]
        if fahrenheit { items.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit")) }
        components?.queryItems = items
        return components?.url
    }

    static func weather(from data: Data) -> WeatherReport? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (current["weather_code"] as? NSNumber)?.intValue else { return nil }
        let isDay = ((current["is_day"] as? NSNumber)?.intValue ?? 1) == 1
        let unit = ((object["current_units"] as? [String: Any])?["temperature_2m"] as? String) ?? "°"
        var days: [WeatherDay] = []
        if let daily = object["daily"] as? [String: Any],
           let dates = daily["time"] as? [String],
           let codes = daily["weather_code"] as? [Any],
           let highs = daily["temperature_2m_max"] as? [Any],
           let lows = daily["temperature_2m_min"] as? [Any] {
            for index in dates.indices where index < codes.count && index < highs.count && index < lows.count {
                guard let dayCode = (codes[index] as? NSNumber)?.intValue,
                      let high = (highs[index] as? NSNumber)?.doubleValue,
                      let low = (lows[index] as? NSNumber)?.doubleValue else { continue }
                days.append(WeatherDay(date: dates[index], code: dayCode, high: high, low: low))
            }
        }
        return WeatherReport(temperature: temperature, code: code, isDay: isDay, unit: unit, days: days)
    }

    /// The SF Symbol for a WMO weather code.
    static func weatherSymbol(code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func weatherDescription(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return "Weather"
        }
    }

    // MARK: Hiding parts of a page

    /// A script that hides the parts of a page you picked (run on every load).
    static func hideElementsScript(_ selectors: [String]) -> String {
        let css = selectors.map { $0 + " { display: none !important; }" }.joined(separator: "\n")
        let literal = (try? JSONSerialization.data(withJSONObject: [css])).map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
        return """
        (function() {
          var css = \(literal)[0];
          var style = document.getElementById('notchflow-glance-hidden');
          if (!style) { style = document.createElement('style'); style.id = 'notchflow-glance-hidden'; (document.head || document.documentElement).appendChild(style); }
          style.textContent = css;
        })();
        """
    }

    /// A script that lets you click the part of a page to hide: it outlines
    /// what's under the pointer and sends the clicked element's selector to
    /// NotchFlow ("glanceHide"); Esc cancels.
    static let pickElementScript = """
    (function() {
      if (window.__notchflowPicking) return;
      window.__notchflowPicking = true;
      var box = document.createElement('div');
      box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #0a84ff;background:rgba(10,132,255,.15);border-radius:4px;transition:all .05s';
      document.documentElement.appendChild(box);
      function selector(el) {
        if (el.id) return '#' + CSS.escape(el.id);
        var parts = [];
        while (el && el.nodeType === 1 && el !== document.body && parts.length < 6) {
          var part = el.tagName.toLowerCase();
          if (el.classList.length) part += '.' + Array.from(el.classList).slice(0, 2).map(CSS.escape).join('.');
          var parent = el.parentElement;
          if (parent) {
            var same = Array.from(parent.children).filter(function (c) { return c.tagName === el.tagName; });
            if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(el) + 1) + ')';
          }
          parts.unshift(part);
          el = parent;
          if (el && el.id) { parts.unshift('#' + CSS.escape(el.id)); break; }
        }
        return parts.join(' > ');
      }
      function move(e) {
        var r = e.target.getBoundingClientRect();
        box.style.left = r.left + 'px'; box.style.top = r.top + 'px';
        box.style.width = r.width + 'px'; box.style.height = r.height + 'px';
      }
      function click(e) {
        e.preventDefault(); e.stopPropagation();
        var picked = selector(e.target);
        done();
        window.webkit.messageHandlers.glanceHide.postMessage(picked);
      }
      function key(e) { if (e.key === 'Escape') { e.preventDefault(); done(); } }
      function done() {
        document.removeEventListener('mousemove', move, true);
        document.removeEventListener('click', click, true);
        document.removeEventListener('keydown', key, true);
        box.remove();
        window.__notchflowPicking = false;
      }
      document.addEventListener('mousemove', move, true);
      document.addEventListener('click', click, true);
      document.addEventListener('keydown', key, true);
    })();
    """

    /// The folder agents (Claude Code, Codex…) write HTML widgets into, inside Application Support/NotchFlow.
    static let agentWidgetsFolder = "Glance Widgets"
}
