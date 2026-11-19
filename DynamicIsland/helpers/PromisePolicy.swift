// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// A promise found in a message: one you made ("I'll send it tonight") or one
/// made to you ("I'll send the invoice Monday").
struct PromiseCandidate: Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case mine, theirs }
    let kind: Kind
    /// "Send Sam the deck", "send me the invoice".
    let title: String
    let due: Date
    /// False when no time was said and a default was picked.
    let hasExplicitTime: Bool
}

/// Finds promises in chat messages, on this Mac, from phrases and dates
/// alone. Foundation only, so Build.command can check it alone.
enum PromisePolicy {
    // MARK: Detection

    /// Phrases that start a commitment, longest first.
    private static let triggers = [
        "i'll try to ", "i will try to ", "i'm going to ", "i am going to ", "i'm gonna ", "im gonna ",
        "i'll ", "i will ", "ill ", "let me ", "will ",
    ]
    /// Short replies that commit without saying to what.
    private static let bareCommitments = ["will do", "on it", "sure will", "consider it done", "leave it with me"]
    /// Look like a trigger but are not a promise.
    private static let notPromises = [
        "let me know", "let me guess", "let me see if you", "i'll never", "i will never", "i will not", "i'll not",
        "will you", "will it", "will they", "will we", "will he", "will she", "will this", "will that",
        "i'll be honest", "i will be honest", "i'll admit", "let me be honest", "i'll take that as",
        "let me tell you", "let me explain", "i'll pass", "i'll think about it", "will see", "we will see",
    ]

    /// The first promise in a message, if any.
    static func detect(_ text: String, fromMe: Bool, now: Date, calendar: Calendar = .current) -> PromiseCandidate? {
        let normalized = text.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        for (sentence, isQuestion) in sentences(normalized) where !isQuestion {
            let lower = sentence.lowercased()
            guard !notPromises.contains(where: { lower.contains($0) }) else { continue }
            var action: String?
            if let bare = bareCommitments.first(where: { lower.hasPrefix($0) || lower == $0 }) {
                action = String(lower.dropFirst(bare.count))
                if action?.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).isEmpty ?? true { action = "" }
            } else {
                for trigger in triggers {
                    guard let range = triggerRange(trigger, in: lower) else { continue }
                    // A bare "will" needs to start the sentence ("will send it tonight").
                    if trigger == "will " && range.lowerBound != lower.startIndex { continue }
                    action = String(lower[range.upperBound...])
                    break
                }
            }
            guard let rawAction = action else { continue }
            let (due, explicit) = dueDate(in: lower, now: now, calendar: calendar)
            var title = cleanAction(rawAction)
            if title.isEmpty { title = "Follow up" }
            // Something that already happened ("I'll" about the past) is rare; a
            // promise with neither an action nor a time is too vague to track.
            if title == "Follow up" && !explicit { continue }
            title = String(title.prefix(80))
            return PromiseCandidate(kind: fromMe ? .mine : .theirs, title: capitalized(title), due: due, hasExplicitTime: explicit)
        }
        return nil
    }

    private static func triggerRange(_ trigger: String, in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while let range = text.range(of: trigger, range: start..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            if beforeOK { return range }
            start = range.upperBound
        }
        return nil
    }

    /// Sentences, each with whether it was a question.
    private static func sentences(_ text: String) -> [(String, Bool)] {
        var result: [(String, Bool)] = []
        var current = ""
        for character in text {
            if character == "." || character == "!" || character == "?" || character == "\n" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append((trimmed, character == "?")) }
                current = ""
            } else {
                current.append(character)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { result.append((trimmed, false)) }
        return result
    }

    // MARK: Titles

    private static let timePhrases = [
        "first thing tomorrow morning", "first thing tomorrow", "tomorrow morning", "tomorrow afternoon",
        "tomorrow evening", "tomorrow night", "this afternoon", "this evening", "this morning", "this weekend",
        "end of day", "end of the day", "later today", "next week", "by eod", "eod", "tonight", "tomorrow",
        "today", "asap", "as soon as possible", "in a bit", "in a few minutes", "in a few mins", "in a while",
        "shortly", "soon", "later", "right away", "right now",
    ]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let fillers = ["definitely ", "probably ", "surely ", "quickly ", "just ", "also "]

    private static func cleanAction(_ raw: String) -> String {
        var text = " " + raw.trimmingCharacters(in: .whitespaces) + " "
        // Clock times and relative times ("at 5pm", "by 17:00", "in 2 hours").
        let patterns = [
            #"\s(by|at|around|before|until)\s+\d{1,2}([:.]\d{2})?\s*(am|pm)?(?=\W)"#,
            #"\s\d{1,2}([:.]\d{2})?\s*(am|pm)(?=\W)"#,
            #"\s(in|within)\s+(an?|half an|\d+)\s+(minutes?|mins?|hours?|hrs?|h|days?)(?=\W)"#,
            #"\s(by|on|this|next|before)?\s*(sunday|monday|tuesday|wednesday|thursday|friday|saturday)(\s+(morning|afternoon|evening|night))?(?=\W)"#,
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        for phrase in timePhrases {
            text = text.replacingOccurrences(of: #"\s(by\s+|before\s+|until\s+)?"# + NSRegularExpression.escapedPattern(for: phrase) + #"(?=\W)"#,
                                             with: " ", options: .regularExpression)
        }
        for filler in fillers { text = text.replacingOccurrences(of: " " + filler, with: " ") }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    }

    /// Puts the other person in: "send you the deck" → "send Sam the deck"
    /// for your promises, "send you the invoice" → "send me the invoice" for theirs.
    static func personalized(_ title: String, kind: PromiseCandidate.Kind, person: String) -> String {
        let first = firstName(person)
        var words = title.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for index in words.indices {
            let word = words[index]
            let core = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            let tail = String(word.drop(while: { $0.isLetter }))
            switch (kind, core) {
            case (.mine, "you") where !first.isEmpty: words[index] = first + tail
            case (.mine, "your") where !first.isEmpty: words[index] = first + "'s" + tail
            case (.theirs, "you"): words[index] = "me" + tail
            case (.theirs, "your"): words[index] = "my" + tail
            default: break
            }
        }
        return capitalized(words.joined(separator: " "))
    }

    static func firstName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("+"), !trimmed.isEmpty else { return "" }
        return String(trimmed.split(separator: " ").first ?? "")
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Dates

    /// When the promise is due, and whether a time was actually said.
    static func dueDate(in lower: String, now: Date, calendar: Calendar = .current) -> (Date, Bool) {
        func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? now
        }
        /// Today at that time, or in an hour if that time already passed.
        func todayAt(_ hour: Int, _ minute: Int = 0) -> Date {
            let date = at(hour, minute)
            return date > now ? date : now.addingTimeInterval(3600)
        }
        let padded = " " + lower + " "

        // Relative: "in 2 hours", "in 30 min", "in an hour", "in half an hour".
        if let match = padded.range(of: #"\s(in|within)\s+(an?|half an|\d+)\s+(minutes?|mins?|hours?|hrs?|h|days?)\W"#, options: .regularExpression) {
            let words = padded[match].split(whereSeparator: { $0 == " " || !$0.isLetter && !$0.isNumber }).map(String.init)
            let amountWord = words.count > 1 ? words[1] : "1"
            var amount: Double = amountWord == "half" ? 0.5 : Double(amountWord) ?? 1
            let unit = words.last ?? "hour"
            if unit.hasPrefix("min") { amount *= 60 } else if unit.hasPrefix("day") { amount *= 86_400 } else { amount *= 3600 }
            return (now.addingTimeInterval(amount), true)
        }

        // A clock time, optionally with a day word.
        var dayOffset: Int?
        if padded.contains("tomorrow") { dayOffset = 1 }
        if dayOffset == nil, let weekday = weekdays.firstIndex(where: { padded.contains(" \($0)") || padded.contains("\($0) ") }) {
            let today = calendar.component(.weekday, from: now) - 1
            var offset = (weekday - today + 7) % 7
            if offset == 0 && (padded.contains("next \(weekdays[weekday])") || calendar.component(.hour, from: now) >= 17) { offset = 7 }
            dayOffset = offset
        }
        if let time = clockTime(in: padded) {
            let offset = dayOffset ?? 0
            let date = at(time.hour, time.minute, dayOffset: offset)
            if offset == 0 && date <= now { return (at(time.hour, time.minute, dayOffset: 1), true) }
            return (date, true)
        }

        if padded.contains("tomorrow morning") || padded.contains("first thing tomorrow") { return (at(9, dayOffset: 1), true) }
        if padded.contains("tomorrow afternoon") { return (at(15, dayOffset: 1), true) }
        if padded.contains("tomorrow evening") || padded.contains("tomorrow night") { return (at(20, dayOffset: 1), true) }
        if padded.contains("tomorrow") { return (at(10, dayOffset: 1), true) }
        if padded.contains("tonight") || padded.contains("this evening") { return (todayAt(20), true) }
        if padded.contains("this afternoon") { return (todayAt(15), true) }
        if padded.contains("this morning") { return (todayAt(11), true) }
        if padded.contains("end of day") || padded.contains("end of the day") || padded.contains(" eod") || padded.contains(" today") {
            return (todayAt(18), true)
        }
        if padded.contains("this weekend") {
            let today = calendar.component(.weekday, from: now) - 1
            return (at(11, dayOffset: max(0, (6 - today + 7) % 7)), true)
        }
        if padded.contains("next week") {
            let today = calendar.component(.weekday, from: now) - 1
            return (at(10, dayOffset: (1 - today + 7) % 7 == 0 ? 7 : (1 - today + 7) % 7), true)
        }
        if let offset = dayOffset { return (at(17, dayOffset: offset), true) }
        if padded.contains("asap") || padded.contains("right away") || padded.contains("right now") || padded.contains("in a bit")
            || padded.contains("shortly") || padded.contains(" soon") || padded.contains("in a few") {
            return (now.addingTimeInterval(3600), true)
        }
        if padded.contains("later") { return (min(now.addingTimeInterval(3 * 3600), max(todayAt(21), now.addingTimeInterval(3600))), true) }
        // Nothing said: a day is a fair window for "let me check and get back to you".
        return (now.addingTimeInterval(86_400), false)
    }

    private static func clockTime(in padded: String) -> (hour: Int, minute: Int)? {
        let patterns = [
            #"\s(by|at|around|before|until)\s+(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\W"#,
            #"\s(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\W"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: padded, range: NSRange(padded.startIndex..., in: padded)) else { continue }
            func group(_ number: Int) -> String? {
                let range = match.range(at: number)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: padded) else { return nil }
                return String(padded[swiftRange])
            }
            let offset = index == 0 ? 1 : 0
            guard var hour = group(1 + offset).flatMap(Int.init) else { continue }
            let minute = group(2 + offset).flatMap(Int.init) ?? 0
            let meridiem = group(3 + offset)
            guard hour <= 23, minute <= 59 else { continue }
            if meridiem == "pm" && hour < 12 { hour += 12 }
            if meridiem == "am" && hour == 12 { hour = 0 }
            // "at 5" with no am/pm during the day means 5 pm.
            if meridiem == nil && hour >= 1 && hour <= 7 { hour += 12 }
            return (hour, minute)
        }
        return nil
    }

    // MARK: Nudges and drafts

    /// When to nudge: an hour (or `lead`) before it is due, never in the past.
    static func nudgeDate(due: Date, lead: TimeInterval, created: Date) -> Date {
        max(due.addingTimeInterval(-lead), created.addingTimeInterval(5 * 60))
    }

    /// A message for when you're running late, or a polite check-in for theirs.
    static func followUpDraft(kind: PromiseCandidate.Kind, title: String, person: String) -> String {
        let first = firstName(person)
        let what = title.prefix(1).lowercased() + title.dropFirst()
        switch kind {
        case .mine:
            return "Sorry, running a bit behind on this (\(what)). Is tomorrow morning okay?"
        case .theirs:
            return (first.isEmpty ? "Hi" : "Hi \(first)") + ", just checking in on this (\(what)). Thanks!"
        }
    }
}
