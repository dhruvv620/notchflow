// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Completed Pomodoro focus sessions and what they add up to.
/// Pure logic (Foundation only), so Build.command can check it alone.
struct FocusSessionRecord: Codable, Equatable, Sendable {
    let endedAt: Date
    let minutes: Double
}

enum FocusHistoryPolicy {
    static let keepDays = 90

    static func appending(_ record: FocusSessionRecord, to records: [FocusSessionRecord], now: Date) -> [FocusSessionRecord] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return (records + [record]).filter { $0.endedAt >= cutoff && $0.minutes > 0 && $0.minutes.isFinite }
    }

    /// Minutes of focus for each of the last seven days, oldest first, ending today.
    static func lastSevenDays(_ records: [FocusSessionRecord], now: Date, calendar: Calendar = .current) -> [(day: Date, minutes: Double)] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset -> (day: Date, minutes: Double)? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let minutes = records.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
            return (day, minutes)
        }
    }

    static func minutes(on day: Date, in records: [FocusSessionRecord], calendar: Calendar = .current) -> Double {
        records.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
    }

    /// Consecutive days with focus, counting back from today (or from
    /// yesterday when nothing has been done yet today).
    static func streak(_ records: [FocusSessionRecord], now: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if minutes(on: day, in: records, calendar: calendar) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while minutes(on: day, in: records, calendar: calendar) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// "1h 25m", "40m".
    static func durationLabel(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total >= 60 { return total % 60 == 0 ? "\(total / 60)h" : "\(total / 60)h \(total % 60)m" }
        return "\(total)m"
    }
}
