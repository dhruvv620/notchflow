// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Orbit's day rhythm: your best focus hours, noticing when you're scattered
// across apps, the end-of-day shutdown, and bills or renewals spotted in your
// messages. Pure, tested in tests/OrbitRegression.swift.

/// A renewal or bill seen in a message.
struct OrbitBill: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var service: String
    var amount: String?
    var due: Date?
    var source: String
    let seen: Date
    var snippet: String
}

enum OrbitRhythmPolicy {
    // MARK: Best focus hours

    /// Deep work: making things, not talking about them.
    static let deepCategories: Set<TimeCategory> = [.coding, .writing, .design, .learning]

    struct FocusWindow: Equatable, Sendable {
        let start: Int
        let end: Int
        /// Average minutes of deep work in the window on days you worked.
        let averageMinutes: Int
        let days: Int
    }

    /// The `length`-hour window between `from` and `to` with the most deep work
    /// on average, from at least `minDays` days with any tracked time.
    static func bestFocusWindow(logs: [TimeDayLog], length: Int = 2, from: Int = 6, to: Int = 22,
                                minDays: Int = 3, minMinutes: Int = 30) -> FocusWindow? {
        let days = logs.filter { $0.total > 0 }
        guard days.count >= minDays, length > 0, to - from >= length else { return nil }
        var perHour = [Double](repeating: 0, count: 24)
        for log in days {
            for hour in from..<to {
                perHour[hour] += log.hour(hour).filter { deepCategories.contains($0.key) }.values.reduce(0, +)
            }
        }
        var best: (start: Int, seconds: Double)?
        for start in from...(to - length) {
            let seconds = (start..<(start + length)).reduce(0) { $0 + perHour[$1] }
            if best == nil || seconds > best!.seconds { best = (start, seconds) }
        }
        guard let best else { return nil }
        let average = Int((best.seconds / Double(days.count) / 60).rounded())
        guard average >= minMinutes else { return nil }
        return FocusWindow(start: best.start, end: best.start + length, averageMinutes: average, days: days.count)
    }

    static func hourText(_ hour: Int) -> String { String(format: "%02d:00", hour % 24) }

    /// The next time the window starts: today if it's still ahead, else nil.
    static func startToday(_ window: FocusWindow, now: Date, calendar: Calendar = .current) -> Date? {
        guard let start = calendar.date(bySettingHour: window.start, minute: 0, second: 0, of: now) else { return nil }
        return start
    }

    // MARK: Scattered

    struct Switch: Equatable, Sendable {
        let date: Date
        let app: String
    }

    /// Switches and different apps in the last `window` seconds.
    static func scatter(_ switches: [Switch], now: Date, window: TimeInterval = 600) -> (switches: Int, apps: Int) {
        let recent = switches.filter { now.timeIntervalSince($0.date) <= window && $0.date <= now }
        return (recent.count, Set(recent.map(\.app)).count)
    }

    /// Jumping between at least 6 apps with at least 10 switches in 10 minutes.
    static func isScattered(switches: Int, apps: Int, minSwitches: Int = 10, minApps: Int = 6) -> Bool {
        switches >= minSwitches && apps >= minApps
    }

    /// Drops switches older than the window (keeps memory small).
    static func trimmed(_ switches: [Switch], now: Date, window: TimeInterval = 600) -> [Switch] {
        switches.filter { now.timeIntervalSince($0.date) <= window }
    }

    // MARK: Shutdown

    /// Tomorrow's top three: what's due first, then what needs you most;
    /// replies only if nothing else.
    static func tomorrowTop(_ loops: [OrbitLoop], now: Date, limit: Int = 3) -> [OrbitLoop] {
        let dueSoon = now.addingTimeInterval(36 * 3600)
        let ranked = loops.sorted { a, b in
            let aDue = a.due.map { $0 <= dueSoon } ?? false
            let bDue = b.due.map { $0 <= dueSoon } ?? false
            if aDue != bDue { return aDue }
            if (a.kind == .message) != (b.kind == .message) { return b.kind == .message }
            if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
            return a.date > b.date
        }
        return Array(ranked.prefix(limit))
    }

    /// "wip/2026-11-24": where unsaved code is backed up at shutdown.
    static func backupBranch(day: String) -> String { "wip/notchflow-\(day)" }

    /// Quiet until the morning brief's hour tomorrow (minutes from now).
    static func minutesUntilMorning(now: Date, hour: Int, calendar: Calendar = .current) -> Int {
        let next = OrbitTeamPolicy.nextBriefDate(after: now, hour: hour, calendar: calendar)
        return max(1, Int(next.timeIntervalSince(now) / 60))
    }

    // MARK: Bills and renewals

    static let billPhrases = ["will renew", "renews on", "renews ", "auto-renew", "autorenew", "subscription renew",
                              "trial ends", "trial will end", "trial is ending", "payment due", "payment is due",
                              "bill is due", "bill due", "due date", "will be charged", "you'll be charged",
                              "auto-pay", "autopay", "invoice due", "membership renews", "renewal"]
    static let doneWords = ["payment received", "thank you for your payment", "was successful", "has been paid",
                            "paid successfully", "receipt for", "refund", "cancelled", "canceled"]

    /// Whether a message talks about an upcoming charge (not a receipt).
    static func isBillMessage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        guard billPhrases.contains(where: { lowered.contains($0) }) else { return false }
        return !doneWords.contains(where: { lowered.contains($0) })
    }

    /// "$9.99", "₹199", "€12,50", "15.00 USD".
    static func amount(in text: String) -> String? {
        let patterns = [#"[$€£₹¥]\s?\d{1,6}(?:[.,]\d{2})?"#, #"\d{1,6}(?:[.,]\d{2})?\s?(?:USD|EUR|GBP|INR|CAD|AUD)\b"#,
                        #"(?:Rs\.?|INR)\s?\d{1,6}(?:[.,]\d{2})?"#]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(text[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The service a bill is for: a known name in the text, else the sender.
    static func service(in text: String, sender: String, app: String) -> String {
        let known = ["Netflix", "Spotify", "Apple", "iCloud", "Amazon", "Prime", "YouTube", "Google", "Adobe", "Microsoft",
                     "Disney", "Hulu", "ChatGPT", "OpenAI", "Claude", "Anthropic", "GitHub", "Notion", "Figma", "Dropbox",
                     "Canva", "Duolingo", "Audible", "Uber", "Airtel", "Jio", "Vodafone", "Verizon", "AT&T", "T-Mobile"]
        if let name = known.first(where: { text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b",
                                                      options: [.regularExpression, .caseInsensitive]) != nil }) {
            return name
        }
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? app : String(trimmed.prefix(40))
    }

    static func billID(service: String, due: Date?, calendar: Calendar = .current) -> String {
        "bill:\(OrbitPolicy.key(service))|\(due.map { OrbitPolicy.dayKey($0, calendar: calendar) } ?? "undated")"
    }

    /// Bills show in Loops from three days before they're due (undated: right away),
    /// and stop a week after.
    static func isVisible(_ bill: OrbitBill, now: Date) -> Bool {
        guard let due = bill.due else { return now.timeIntervalSince(bill.seen) < 7 * 86_400 }
        return now >= due.addingTimeInterval(-3 * 86_400) && now <= due.addingTimeInterval(7 * 86_400)
    }

    static func loop(for bill: OrbitBill, calendar: Calendar = .current) -> OrbitLoop {
        var title = "\(bill.service) renews"
        if let amount = bill.amount { title += " · \(amount)" }
        let detail = bill.due.map { "Due \(OrbitPolicy.dayKey($0, calendar: calendar)) · from \(bill.source)" } ?? "From \(bill.source)"
        return OrbitLoop(id: bill.id, kind: .bill, title: title, detail: detail, date: bill.seen, due: bill.due)
    }
}
