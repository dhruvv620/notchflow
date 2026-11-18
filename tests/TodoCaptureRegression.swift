// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct TodoCaptureRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "TodoCaptureRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(TodoCapturePolicy.title(fromText: "\n\n  Buy   milk \nand eggs") == "Buy milk", "First line not used")
        try require(TodoCapturePolicy.title(fromText: "   \n ") == nil, "Blank text accepted")
        let long = String(repeating: "word ", count: 60)
        let shortened = TodoCapturePolicy.title(fromText: long) ?? ""
        try require(shortened.hasSuffix("…") && shortened.count <= TodoCapturePolicy.maximumTitleLength + 1, "Long text not shortened")
        try require(TodoCapturePolicy.title(fromURL: URL(string: "https://www.example.com/article/1")!) == "Read example.com/article/1", "Link title wrong")
        try require(TodoCapturePolicy.title(fromURL: URL(fileURLWithPath: "/tmp/Invoice March.pdf")) == "Open Invoice March", "File title wrong")
        try require(TodoCapturePolicy.title(fromURL: URL(string: "mailto:sam@example.com?subject=Hi")!) == "Email sam@example.com", "Email title wrong")
        try require(TodoCapturePolicy.followUpTitle(sender: "Selene", body: "Are you coming?\nSeat saved") == "Reply to Selene: Are you coming?", "Follow-up title wrong")
        try require(TodoCapturePolicy.followUpTitle(sender: "", body: "") == "Follow up", "Empty follow-up wrong")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 14 Nov 2023, 22:13 UTC
        let earlier = now.addingTimeInterval(-3600)
        let yesterday = now.addingTimeInterval(-86_400 * 2)
        let tomorrow = now.addingTimeInterval(86_400)
        let progress = TodoCapturePolicy.todayProgress([
            (isCompleted: true, dueDate: earlier, completionDate: now),         // done today
            (isCompleted: false, dueDate: earlier, completionDate: nil),        // open today
            (isCompleted: false, dueDate: yesterday, completionDate: nil),      // overdue counts
            (isCompleted: false, dueDate: tomorrow, completionDate: nil),       // later: not today
            (isCompleted: false, dueDate: nil, completionDate: nil),            // undated: not today
            (isCompleted: true, dueDate: yesterday, completionDate: yesterday), // done another day
        ], now: now, calendar: calendar)
        try require(progress == TodoCapturePolicy.Progress(done: 1, total: 3), "Today progress wrong: \(progress)")
        try require(TodoCapturePolicy.Progress(done: 0, total: 0).fraction == 0, "Empty progress not zero")
        print("Todo capture checks passed")
    }
}
