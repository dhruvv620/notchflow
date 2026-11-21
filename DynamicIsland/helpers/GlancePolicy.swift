// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// What a Glance panel shows.
enum GlancePanelKind: String, Codable, CaseIterable, Sendable {
    case web, pdf, window, calendar, reminders, clocks, stocks, promises, setups, stash, whatsapp

    /// Built-in panels exist once on a board; web pages, PDFs and app
    /// windows as many times as you add them.
    var isBuiltIn: Bool { self != .web && self != .pdf && self != .window }

    var defaultTitle: String {
        switch self {
        case .web: return "Web page"
        case .pdf: return "PDF"
        case .window: return "App window"
        case .calendar: return "Today"
        case .reminders: return "Reminders"
        case .clocks: return "World clocks"
        case .stocks: return "Stocks"
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
        case .window: return "macwindow"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .clocks: return "clock"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .promises: return "hand.raised"
        case .setups: return "rectangle.3.group"
        case .stash: return "tray.full"
        case .whatsapp: return "message"
        }
    }

    /// Size in grid cells when added.
    var defaultSize: (width: Int, height: Int) {
        switch self {
        case .web, .pdf, .window: return (3, 2)
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
    /// Stocks: ticker symbols ("AAPL", "RELIANCE.NS").
    var symbols: [String] = []
    /// App window: the app (bundle id) and the window's title when picked.
    var windowApp = ""
    var windowTitle = ""
    /// Off: kept in the list but not on the board.
    var isShown = true
    var frame: GlanceRect

    init(id: UUID = UUID(), kind: GlancePanelKind, title: String, address: String = "", refreshMinutes: Int = 5,
         mobileLayout: Bool = false, timeZones: [String] = [], symbols: [String] = [], windowApp: String = "",
         windowTitle: String = "", isShown: Bool = true, frame: GlanceRect) {
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
        self.isShown = isShown
        self.frame = frame
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, address, refreshMinutes, mobileLayout, timeZones, symbols, windowApp, windowTitle, isShown, frame
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
        isShown = try values.decodeIfPresent(Bool.self, forKey: .isShown) ?? true
        frame = try values.decode(GlanceRect.self, forKey: .frame)
    }
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
    static func boardsToShow(displays: [String], pointer: String?, assignments: [String: UUID],
                             selected: UUID, boards: Set<UUID>) -> [String: UUID] {
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

    // MARK: Hold or tap

    /// Released this soon after pressing, the shortcut was a tap: the board stays open.
    static let tapLimit: TimeInterval = 0.35

    static func isTap(heldFor seconds: TimeInterval) -> Bool { seconds < tapLimit }
}
