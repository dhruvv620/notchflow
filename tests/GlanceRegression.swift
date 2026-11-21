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

        // Grid
        try require(R(x: 0, y: 0, width: 2, height: 2).intersects(R(x: 1, y: 1, width: 2, height: 2))
                    && !R(x: 0, y: 0, width: 2, height: 2).intersects(R(x: 2, y: 0, width: 2, height: 2)), "Intersects")
        try require(P.clamped(R(x: 5, y: 3, width: 3, height: 3)) == R(x: 3, y: 1, width: 3, height: 3)
                    && P.clamped(R(x: -1, y: 0, width: 0, height: 9)) == R(x: 0, y: 0, width: 1, height: 4), "Clamped")

        // Starter board: four panels filling the grid, nothing overlapping
        let starter = P.starterBoard()
        try require(starter.panels.map(\.kind) == [.calendar, .reminders, .promises, .clocks], "Starter kinds")
        try require(starter.panels.allSatisfy(\.isShown)
                    && starter.panels.map { $0.frame.width * $0.frame.height }.reduce(0, +) == P.columns * P.rows,
                    "Starter layout: \(starter.panels.map(\.frame))")
        try require(starter.panels[3].timeZones == P.defaultTimeZones, "Clocks get time zones")
        func noOverlaps(_ board: GlanceBoard) -> Bool {
            let shown = board.panels.filter(\.isShown)
            for (i, a) in shown.enumerated() { for b in shown.dropFirst(i + 1) where a.frame.intersects(b.frame) { return false } }
            return shown.allSatisfy { P.clamped($0.frame) == $0.frame }
        }
        try require(noOverlaps(starter), "Starter overlaps")

        // Adding: goes where there's room; a full board hides it
        var board = GlanceBoard(name: "Test")
        board = P.adding(.web, title: "GitHub", address: "github.com", to: board)
        try require(board.panels[0].frame == R(x: 0, y: 0, width: 3, height: 2) && board.panels[0].title == "GitHub", "First web panel")
        board = P.adding(.web, to: board)
        try require(board.panels[1].frame == R(x: 3, y: 0, width: 3, height: 2), "Second beside it")
        board = P.adding(.pdf, to: board)
        board = P.adding(.pdf, to: board)
        try require(board.panels[2].frame == R(x: 0, y: 2, width: 3, height: 2) && board.panels[3].frame == R(x: 3, y: 2, width: 3, height: 2),
                    "Bottom row")
        board = P.adding(.calendar, to: board)
        try require(!board.panels[4].isShown && noOverlaps(board), "Full board: added hidden")

        // Hiding frees room; showing again finds it
        board = P.setting(board.panels[3].id, shown: false, on: board)
        board = P.setting(board.panels[4].id, shown: true, on: board)
        try require(board.panels[4].isShown && board.panels[4].frame.x >= 3 && board.panels[4].frame.y == 2 && noOverlaps(board),
                    "Shown into the free room: \(board.panels[4].frame)")

        // Moving: onto empty space, and swapping
        var two = GlanceBoard(name: "Two")
        two = P.adding(.calendar, to: two)   // 0,0 2x2
        two = P.adding(.reminders, to: two)  // 2,0 2x2
        let a = two.panels[0].id, b = two.panels[1].id
        let moved = P.moving(a, toX: 4, y: 2, on: two)
        try require(moved.panels[0].frame == R(x: 4, y: 2, width: 2, height: 2), "Moved into empty space")
        let clampedMove = P.moving(a, toX: 5, y: 3, on: two)
        try require(clampedMove.panels[0].frame == R(x: 4, y: 2, width: 2, height: 2), "Moved, kept inside the grid")
        let swapped = P.moving(a, toX: 2, y: 0, on: two)
        try require(swapped.panels[0].frame == R(x: 2, y: 0, width: 2, height: 2) && swapped.panels[1].frame == R(x: 0, y: 0, width: 2, height: 2),
                    "Swapped")
        try require(P.moving(b, toX: 2, y: 0, on: two) == two, "Dropped where it is: unchanged")

        // Resizing only into clear space
        let wider = P.resizing(a, width: 2, height: 4, on: two)
        try require(wider.panels[0].frame == R(x: 0, y: 0, width: 2, height: 4), "Taller")
        try require(P.resizing(a, width: 3, height: 2, on: two) == two, "Can't grow into a neighbour")
        try require(P.resizing(a, width: 9, height: 9, on: P.removing(b, from: two)).panels[0].frame == R(x: 0, y: 0, width: 6, height: 4),
                    "Capped at the grid")

        // Presets
        let dashboard = P.applying(P.presets[1], to: starter)
        try require(dashboard.panels.map(\.frame) == Array(P.presets[1].slots.prefix(4)) && noOverlaps(dashboard), "Dashboard preset")
        let halves = P.applying(P.presets[2], to: starter)
        try require(halves.panels.filter(\.isShown).count == 2 && noOverlaps(halves), "Two halves: the rest hidden: \(halves.panels.map(\.frame))")
        let wide = P.applying(P.presets[3], to: P.removing(starter.panels[3].id, from: starter))
        try require(wide.panels.filter(\.isShown).count == 3 && noOverlaps(wide), "Fewer panels than slots")
        try require(P.presets.allSatisfy { preset in
            preset.slots.allSatisfy { P.clamped($0) == $0 }
                && preset.slots.enumerated().allSatisfy { i, s in preset.slots.dropFirst(i + 1).allSatisfy { !s.intersects($0) } }
        }, "Presets fit and don't overlap")

        // Boards
        let copy = P.duplicate(starter, name: "Copy")
        try require(copy.id != starter.id && copy.name == "Copy" && copy.panels.count == 4
                    && Set(copy.panels.map(\.id)).isDisjoint(with: starter.panels.map(\.id))
                    && copy.panels.map(\.frame) == starter.panels.map(\.frame), "Duplicate")
        try require(P.decodeBoards(P.encodeBoards([starter, copy])) == [starter, copy] && P.decodeBoards(Data()).isEmpty, "Round trip")

        // Editor cells
        try require(P.cell(atFractionX: 0, y: 0) == (0, 0) && P.cell(atFractionX: 0.99, y: 0.99) == (5, 3)
                    && P.cell(atFractionX: 0.5, y: 0.5) == (3, 2) && P.cell(atFractionX: 1.4, y: -1) == (5, 0), "Cells")

        // Web pages
        try require(P.webURL("github.com")?.absoluteString == "https://github.com"
                    && P.webURL(" https://mail.google.com/mail ")?.absoluteString == "https://mail.google.com/mail"
                    && P.webURL("http://localhost:3000")?.absoluteString == "http://localhost:3000", "Web URLs")
        try require(P.webURL("") == nil && P.webURL("not a url") == nil && P.webURL("file:///etc/passwd") == nil && P.webURL("hello") == nil,
                    "Not web URLs")
        let now = Date()
        try require(P.needsReload(loadedAt: nil, refreshMinutes: 5, now: now)
                    && P.needsReload(loadedAt: now.addingTimeInterval(-301), refreshMinutes: 5, now: now)
                    && !P.needsReload(loadedAt: now.addingTimeInterval(-60), refreshMinutes: 5, now: now), "Reload due")
        let rules = P.contentRules()
        let parsed = try JSONSerialization.jsonObject(with: Data(rules.utf8)) as? [[String: Any]]
        try require(parsed?.count == P.blockedHosts.count + 1 && rules.contains(#"doubleclick\\.net"#)
                    && rules.contains("css-display-none") && rules.contains("#onetrust-banner-sdk"), "Content rules")

        // Hold or tap
        try require(P.isTap(heldFor: 0.1) && !P.isTap(heldFor: 0.6), "Tap or hold")
        print("Glance: OK")
    }
}
