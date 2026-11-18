// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct FocusHistoryRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "FocusHistoryRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000) // Tue 14 Nov 2023, 22:13 UTC
        func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

        var records: [FocusSessionRecord] = []
        records = FocusHistoryPolicy.appending(.init(endedAt: daysAgo(200), minutes: 25), to: records, now: now)
        try require(records.isEmpty, "Records older than 90 days kept")
        for record in [FocusSessionRecord(endedAt: now, minutes: 25), .init(endedAt: now.addingTimeInterval(-600), minutes: 25),
                       .init(endedAt: daysAgo(1), minutes: 50), .init(endedAt: daysAgo(2), minutes: 25), .init(endedAt: daysAgo(4), minutes: 25)] {
            records = FocusHistoryPolicy.appending(record, to: records, now: now)
        }
        records = FocusHistoryPolicy.appending(.init(endedAt: now, minutes: .nan), to: records, now: now)
        try require(records.count == 5, "Invalid record kept")

        let week = FocusHistoryPolicy.lastSevenDays(records, now: now, calendar: calendar)
        try require(week.count == 7 && week.last?.minutes == 50 && week[5].minutes == 50 && week[3].minutes == 0, "Week totals wrong: \(week.map(\.minutes))")
        try require(FocusHistoryPolicy.streak(records, now: now, calendar: calendar) == 3, "Streak wrong")
        let noFocusYet = records.filter { !calendar.isDate($0.endedAt, inSameDayAs: now) }
        try require(FocusHistoryPolicy.streak(noFocusYet, now: now, calendar: calendar) == 2, "Streak lost before focusing today")
        try require(FocusHistoryPolicy.streak([], now: now, calendar: calendar) == 0, "Empty streak not zero")
        try require(FocusHistoryPolicy.durationLabel(minutes: 85) == "1h 25m" && FocusHistoryPolicy.durationLabel(minutes: 120) == "2h"
                    && FocusHistoryPolicy.durationLabel(minutes: 40) == "40m", "Duration labels wrong")
        print("Focus history checks passed")
    }
}
