// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct GlanceRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "GlanceRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = GlancePolicy
        typealias R = GlanceRect
        let u = P.unit
        /// A rect in coarse (6 × 4) steps.
        func g(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> R { R(x: x * u, y: y * u, width: w * u, height: h * u) }
        func noOverlaps(_ board: GlanceBoard) -> Bool {
            !P.hasOverlaps(board) && board.panels.filter(\.isShown).allSatisfy { P.clamped($0.frame) == $0.frame }
        }

        // Grid
        try require(P.columns == 24 && P.rows == 16, "Fine grid")
        try require(R(x: 0, y: 0, width: 2, height: 2).intersects(R(x: 1, y: 1, width: 2, height: 2))
                    && !R(x: 0, y: 0, width: 2, height: 2).intersects(R(x: 2, y: 0, width: 2, height: 2)), "Intersects")
        try require(R(x: 0, y: 0, width: 4, height: 4).overlap(R(x: 2, y: 2, width: 4, height: 4)) == 4, "Overlap")
        try require(P.clamped(R(x: 22, y: 15, width: 6, height: 6)) == R(x: 18, y: 10, width: 6, height: 6)
                    && P.clamped(R(x: -1, y: 0, width: 0, height: 40)) == R(x: 0, y: 0, width: 1, height: 16), "Clamped")

        // Boards from before the fine grid are scaled up
        let old = #"[{"id":"7E57D0D0-0000-4000-8000-000000000001","name":"Old","panels":[{"id":"7E57D0D0-0000-4000-8000-000000000002","kind":"web","title":"Mail","address":"mail.google.com","refreshMinutes":5,"mobileLayout":false,"timeZones":[],"isShown":true,"frame":{"x":3,"y":0,"width":3,"height":2}},{"id":"7E57D0D0-0000-4000-8000-000000000003","kind":"hologram","title":"?","frame":{"x":0,"y":0,"width":1,"height":1}}]}]"#
        let loaded = P.decodeBoards(Data(old.utf8))
        try require(loaded.count == 1 && loaded[0].panels.count == 1 && loaded[0].panels[0].title == "Mail"
                    && loaded[0].panels[0].frame == g(3, 0, 3, 2) && loaded[0].grid == 24
                    && loaded[0].panels[0].symbols.isEmpty && loaded[0].panels[0].hiddenSelectors.isEmpty, "Old boards load and scale: \(loaded)")
        let again = P.decodeBoards(P.encodeBoards(loaded))
        try require(again == loaded, "Saved boards aren't scaled twice")

        // Starter board fills the grid
        let starter = P.starterBoard()
        try require(starter.panels.map(\.kind) == [.calendar, .reminders, .promises, .clocks], "Starter kinds")
        try require(starter.panels.allSatisfy(\.isShown) && starter.panels.map(\.frame.area).reduce(0, +) == P.columns * P.rows
                    && noOverlaps(starter), "Starter layout")
        try require(starter.panels[3].timeZones == P.defaultTimeZones, "Clocks get time zones")

        // Adding: goes where there's room; a full board hides it
        var board = GlanceBoard(name: "Test")
        board = P.adding(.web, title: "GitHub", address: "github.com", to: board)
        try require(board.panels[0].frame == g(0, 0, 6, 4) && board.panels[0].title == "GitHub", "Web panel fills an empty board")
        board = P.removing(board.panels[0].id, from: board)
        board = P.adding(.calendar, to: board)
        board = P.adding(.reminders, to: board)
        try require(board.panels[0].frame == g(0, 0, 4, 4) && board.panels[1].frame.x == 4 * u, "Side by side: \(board.panels.map(\.frame))")
        board = P.adding(.stash, to: board)
        try require(board.panels[2].isShown && noOverlaps(board), "Smaller size where the default doesn't fit: \(board.panels[2].frame)")

        // Moving: empty space, swap, nearest free spot
        var two = GlanceBoard(name: "Two")
        two = P.adding(.calendar, to: two)
        two = P.adding(.reminders, to: two)
        let a = two.panels[0].id, b = two.panels[1].id
        try require(two.panels[0].frame == g(0, 0, 4, 4) && two.panels[1].frame == R(x: 16, y: 0, width: 8, height: 8),
                    "Two panels: \(two.panels.map(\.frame))")
        var small = GlanceBoard(name: "Small")
        small.panels = [GlancePanel(kind: .calendar, title: "A", frame: R(x: 0, y: 0, width: 8, height: 8)),
                        GlancePanel(kind: .reminders, title: "B", frame: R(x: 8, y: 0, width: 8, height: 8))]
        let sa = small.panels[0].id, sb = small.panels[1].id
        try require(P.moving(sa, toX: 4, y: 9, on: small).panels[0].frame == R(x: 4, y: 8, width: 8, height: 8), "Moved, kept inside")
        let swapped = P.moving(sa, toX: 8, y: 0, on: small)
        try require(swapped.panels[0].frame == R(x: 8, y: 0, width: 8, height: 8) && swapped.panels[1].frame == R(x: 0, y: 0, width: 8, height: 8),
                    "Dropped onto the other: swapped")
        let nudged = P.moving(sa, toX: 14, y: 0, on: small)
        try require(nudged.panels[0].frame == R(x: 16, y: 0, width: 8, height: 8) && nudged.panels[1].frame == small.panels[1].frame,
                    "Dropped partly onto the other: nearest clear spot: \(nudged.panels[0].frame)")
        try require(P.moving(sb, toX: 8, y: 0, on: small) == small, "Dropped where it is: unchanged")
        _ = (a, b)

        // Resizing grows as far as there's room
        let taller = P.resizing(sa, width: 8, height: 16, on: small)
        try require(taller.panels[0].frame == R(x: 0, y: 0, width: 8, height: 16), "Taller")
        let wider = P.resizing(sa, width: 12, height: 8, on: small)
        try require(wider.panels[0].frame == R(x: 0, y: 0, width: 8, height: 8), "Can't grow into a neighbour")
        let capped = P.resizing(sa, width: 99, height: 99, on: P.removing(sb, from: small))
        try require(capped.panels[0].frame == R(x: 0, y: 0, width: 24, height: 16), "Capped at the grid")
        let reframed = P.reframing(sb, to: R(x: 10, y: 2, width: 6, height: 6), on: small)
        try require(reframed.panels[1].frame == R(x: 10, y: 2, width: 6, height: 6), "Top-left edge drag")
        try require(P.reframing(sb, to: R(x: 4, y: 0, width: 6, height: 6), on: small) == small, "Edge drag into a neighbour: unchanged")

        // Presets
        try require(P.presets[1].slots.first == g(0, 0, 2, 2), "Presets on the fine grid")
        let dashboard = P.applying(P.presets[1], to: starter)
        try require(dashboard.panels.map(\.frame) == Array(P.presets[1].slots.prefix(4)) && noOverlaps(dashboard), "Dashboard preset")
        let halves = P.applying(P.presets[2], to: starter)
        try require(halves.panels.filter(\.isShown).count == 2 && noOverlaps(halves), "Two halves: the rest hidden")
        try require(P.presets.allSatisfy { preset in
            preset.slots.allSatisfy { P.clamped($0) == $0 }
                && preset.slots.enumerated().allSatisfy { i, s in preset.slots.dropFirst(i + 1).allSatisfy { !s.intersects($0) } }
        }, "Presets fit and don't overlap")

        // Boards
        let copy = P.duplicate(starter, name: "Copy")
        try require(copy.id != starter.id && copy.name == "Copy" && copy.panels.count == 4
                    && Set(copy.panels.map(\.id)).isDisjoint(with: starter.panels.map(\.id)), "Duplicate")

        // Kinds
        try require(!GlancePanelKind.window.isBuiltIn && !GlancePanelKind.html.isBuiltIn && !GlancePanelKind.weather.isBuiltIn
                    && GlancePanelKind.stocks.isBuiltIn && GlancePanelKind.nowPlaying.isBuiltIn, "Kinds")
        try require(GlancePanelKind.calendar.views.map(\.id) == ["day", "week"] && GlancePanelKind.reminders.views.count == 4, "Views")
        try require(P.adding(.stocks, to: GlanceBoard(name: "S")).panels[0].symbols == P.defaultSymbols, "Stocks get symbols")

        // Web pages
        try require(P.webURL("github.com")?.absoluteString == "https://github.com"
                    && P.webURL("http://localhost:3000")?.absoluteString == "http://localhost:3000", "Web URLs")
        try require(P.webURL("") == nil && P.webURL("not a url") == nil && P.webURL("file:///etc/passwd") == nil, "Not web URLs")
        let now = Date()
        try require(P.needsReload(loadedAt: nil, refreshMinutes: 5, now: now)
                    && !P.needsReload(loadedAt: now.addingTimeInterval(-60), refreshMinutes: 5, now: now), "Reload due")
        let rules = P.contentRules()
        let parsed = try JSONSerialization.jsonObject(with: Data(rules.utf8)) as? [[String: Any]]
        try require(parsed?.count == P.blockedHosts.count + 1 && rules.contains(#"google-analytics\\.com"#)
                    && rules.contains("css-display-none"), "Content rules")
        let hide = P.hideElementsScript(["#ad-banner", "div.promo > a"])
        try require(hide.contains("#ad-banner { display: none !important; }") && hide.contains("notchflow-glance-hidden"), "Hide script")
        try require(P.hideElementsScript(["a[title=\"x\"]"]).contains(#"a[title=\"x\"]"#), "Quotes in selectors are escaped")
        try require(P.pickElementScript.contains("glanceHide") && P.pickElementScript.contains("Escape"), "Picker script")

        // Displays
        let b1 = UUID(), b2 = UUID(), b3 = UUID()
        let all: Set<UUID> = [b1, b2, b3]
        try require(P.boardsToShow(displays: ["A", "B"], pointer: "A", assignments: [:], selected: b1, boards: all) == ["A": b1], "Pointer only")
        try require(P.boardsToShow(displays: ["A", "B"], pointer: "A", assignments: ["B": b2], selected: b1, boards: all) == ["A": b1, "B": b2],
                    "Each display its board")
        try require(P.boardsToShow(displays: ["A", "B"], pointer: "A", assignments: ["B": b1], selected: b1, boards: all) == ["A": b1],
                    "Same board not twice")
        try require(P.boardsToShow(displays: ["A", "B"], pointer: "B", assignments: ["A": b3], selected: b1, boards: all, sameOnAll: true)
                    == ["A": b1, "B": b1], "Same on all displays")

        // Stocks
        try require(P.symbols(from: "aapl, reliance.ns  TSLA,aapl ^NSEI bad$") == ["AAPL", "RELIANCE.NS", "TSLA", "^NSEI"], "Symbols")
        let chart = #"{"chart":{"result":[{"meta":{"currency":"INR","symbol":"RELIANCE.NS","shortName":"RELIANCE","regularMarketPrice":2950.5,"chartPreviousClose":2900.0},"indicators":{"quote":[{"close":[2905.0,null,2950.5]}]}}]}}"#
        let quote = P.quote(from: Data(chart.utf8))
        try require(quote?.points == [2905.0, 2950.5] && quote?.change == 50.5, "Quote")

        // Live windows
        let windows = [P.WindowCandidate(bundleID: "com.google.Chrome", title: "Inbox (3) - Gmail", area: 900_000),
                       P.WindowCandidate(bundleID: "com.google.Chrome", title: "Grafana - Orders", area: 1_200_000),
                       P.WindowCandidate(bundleID: "com.spotify.client", title: "Spotify Premium", area: 600_000)]
        try require(P.pickWindow(windows, app: "com.google.Chrome", title: "Inbox (5) - Gmail") == 0, "Title that changed a little")
        try require(P.pickWindow(windows, app: "com.spotify.client", title: "") == 2 && P.pickWindow(windows, app: "x", title: "") == nil,
                    "App's window")

        // Keys: left and right, recording
        try require(P.Trigger.leftShift.keyCodes == [56] && P.Trigger.forKeyCode(56) == .leftShift && P.Trigger.forKeyCode(60) == .rightShift
                    && P.Trigger.forKeyCode(63) == .fn && P.Trigger.forKeyCode(12) == nil, "Triggers")
        try require(P.isModifierDown(keyCode: 56, flags: 0x20102) && !P.isModifierDown(keyCode: 60, flags: 0x20102)
                    && P.isModifierDown(keyCode: 63, flags: 0x800100), "Modifier down")

        // Hold to peek, tap to keep open
        let t0 = Date()
        var both = P.ModifierGesture(mode: .holdOrTap)
        both.triggerDown(at: t0)
        try require(both.holdElapsed(at: t0.addingTimeInterval(0.25), showing: false) == .show, "Held: peek")
        try require(both.triggerUp(at: t0.addingTimeInterval(1.5), showing: true) == .hide, "Released after a hold: hide")
        both.triggerDown(at: t0)
        try require(both.triggerUp(at: t0.addingTimeInterval(0.12), showing: false) == .pin, "Tap: keep open")
        both.triggerDown(at: t0, pinned: true)
        try require(both.triggerUp(at: t0.addingTimeInterval(0.12), showing: true) == .hide, "Tap while kept open: close")
        both.triggerDown(at: t0)
        _ = both.holdElapsed(at: t0.addingTimeInterval(0.25), showing: false)
        try require(both.triggerUp(at: t0.addingTimeInterval(0.3), showing: true) == .pin, "Quick press that already showed it: keep open")
        both.triggerDown(at: t0)
        both.otherInput(showing: false)
        try require(both.holdElapsed(at: t0.addingTimeInterval(0.5), showing: false) == .none
                    && both.triggerUp(at: t0.addingTimeInterval(0.6), showing: false) == .none, "Typing a capital never opens it")

        var hold = P.ModifierGesture(mode: .hold)
        hold.triggerDown(at: t0)
        try require(hold.triggerUp(at: t0.addingTimeInterval(0.1), showing: false) == .none, "Hold mode: a tap does nothing")
        var toggle = P.ModifierGesture(mode: .toggle)
        toggle.triggerDown(at: t0)
        try require(toggle.holdElapsed(at: t0.addingTimeInterval(0.3), showing: false) == .none
                    && toggle.triggerUp(at: t0.addingTimeInterval(0.15), showing: false) == .toggle, "Toggle")

        // Reminders and calendar views
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_763_726_400)   // 2025-11-21 12:00 UTC
        let yesterday = noon.addingTimeInterval(-86_400), tomorrow = noon.addingTimeInterval(86_400)
        try require(P.reminderMatches(view: "today", due: noon, now: noon, calendar: calendar)
                    && !P.reminderMatches(view: "today", due: tomorrow, now: noon, calendar: calendar), "Today")
        try require(P.reminderMatches(view: "overdue", due: yesterday, now: noon, calendar: calendar)
                    && !P.reminderMatches(view: "overdue", due: noon, now: noon, calendar: calendar), "Overdue")
        try require(P.reminderMatches(view: "scheduled", due: tomorrow, now: noon, calendar: calendar)
                    && !P.reminderMatches(view: "scheduled", due: nil, now: noon, calendar: calendar)
                    && P.reminderMatches(view: "all", due: nil, now: noon, calendar: calendar), "Scheduled and all")
        try require(P.weekDays(from: noon, calendar: calendar).count == 7, "Week")

        // Weather
        try require(P.geocodeURL("Pune")?.absoluteString == "https://geocoding-api.open-meteo.com/v1/search?name=Pune&count=1&language=en&format=json"
                    && P.geocodeURL("  ") == nil, "Geocode URL")
        let place = P.place(from: Data(#"{"results":[{"name":"Pune","latitude":18.51957,"longitude":73.85535,"country":"India"}]}"#.utf8))
        try require(place == P.WeatherPlace(name: "Pune", latitude: 18.51957, longitude: 73.85535), "Place")
        let forecastURL = place.flatMap { P.forecastURL($0, fahrenheit: false) }?.absoluteString ?? ""
        try require(forecastURL.contains("latitude=18.5196") && forecastURL.contains("forecast_days=6") && !forecastURL.contains("fahrenheit"),
                    "Forecast URL: \(forecastURL)")
        let forecast = #"{"current_units":{"temperature_2m":"°C"},"current":{"temperature_2m":27.4,"weather_code":2,"is_day":1},"daily":{"time":["2026-11-21","2026-11-22"],"weather_code":[2,61],"temperature_2m_max":[31.2,29.0],"temperature_2m_min":[17.5,18.1]}}"#
        let report = P.weather(from: Data(forecast.utf8))
        try require(report?.temperature == 27.4 && report?.unit == "°C" && report?.days.count == 2 && report?.days[1].code == 61, "Report")
        try require(P.weatherSymbol(code: 0, isDay: false) == "moon.stars.fill" && P.weatherSymbol(code: 63) == "cloud.rain.fill"
                    && P.weatherDescription(code: 95) == "Thunderstorm", "Weather codes")
        print("Glance: OK")
    }
}
