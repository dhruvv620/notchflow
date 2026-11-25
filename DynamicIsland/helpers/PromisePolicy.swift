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
        let lower = englishTimes(lower)
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

    /// Hindi, Gujarati and Marathi time words in Latin letters, rewritten in
    /// the English the date reader knows: "kal 5 baje" → "tomorrow at 5pm",
    /// "aaje saanje 7 vage" → "today evening at 7pm", "udya sakali 9 vajta" →
    /// "tomorrow morning at 9am". (In a plan, "kal" is tomorrow.)
    static func englishTimes(_ text: String) -> String {
        var result = " " + text.lowercased() + " "
        let words: [(String, String)] = [
            ("parso", "in 2 days"), ("kal", "tomorrow"), ("kale", "tomorrow"), ("kaale", "tomorrow"),
            ("udya", "tomorrow"), ("udyaa", "tomorrow"), ("aaj", "today"), ("aj", "today"), ("aaje", "today"),
            ("aje", "today"), ("subah", "morning"), ("savare", "morning"), ("sakali", "morning"),
            ("dopahar", "afternoon"), ("bapore", "afternoon"), ("dupari", "afternoon"),
            ("shaam", "evening"), ("sham", "evening"), ("saanje", "evening"), ("sanje", "evening"),
            ("sandhyakali", "evening"), ("raat", "night"), ("raate", "night"), ("ratri", "night"),
        ]
        for (word, english) in words {
            result = result.replacingOccurrences(of: #"(?<![a-z])"# + word + #"(?![a-z])"#, with: english, options: .regularExpression)
        }
        let morning = result.contains("morning")
        let night = result.contains("night") || result.contains("evening") || result.contains("afternoon")
        // "5 baje", "5:30 baje", "7 vage", "9 vajta", and a "3pm baje" that already says pm.
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(baje|bje|vage|vagye|vajta|vajata|vajle|o'?clock)(?![a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = result as NSString
        var output = result
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let hour = Int(ns.substring(with: match.range(at: 1))) else { continue }
            let minute = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : nil
            var suffix = match.range(at: 3).location != NSNotFound ? ns.substring(with: match.range(at: 3)) : ""
            if suffix.isEmpty && hour > 12 {
                // Already 24-hour: "17 baje".
                output = (output as NSString).replacingCharacters(in: match.range, with: " at \(hour):\(minute ?? "00") ")
                continue
            }
            if suffix.isEmpty {
                // Plans with friends: 1 to 8 is afternoon or evening unless it's said to be morning.
                if morning { suffix = "am" } else if night || (1...8).contains(hour) || hour == 12 { suffix = "pm" }
                else { suffix = "am" }
            }
            let time = " at \(hour)" + (minute.map { ":\($0)" } ?? "") + suffix + " "
            output = (output as NSString).replacingCharacters(in: match.range, with: time)
        }
        return output
    }

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

// MARK: - Agreed plans

/// "Let's meet for coffee on Friday 5 pm" answered with "okay bhai": a plan
/// both agreed to, kept like a promise ("Coffee with Rahul · Fri 5:00 PM").
extension PromisePolicy {
    /// Words a short yes is made of, in English, Hindi, Gujarati and Marathi
    /// (Latin letters), and the address words that often follow it.
    private static let agreementWords: Set<String> = [
        "ok", "okay", "okk", "okkk", "okie", "okey", "oki", "k", "kk", "sure", "done", "deal", "yes", "yeah", "yea",
        "yep", "yup", "ya", "yaa", "haan", "han", "haa", "hanji", "haanji", "hmm", "hmmm", "pakka", "pakki", "chalo",
        "chal", "chalega", "chalegi", "theek", "thik", "thick", "sahi", "perfect", "great", "cool", "fine", "alright",
        "absolutely", "bilkul", "zaroor", "jarur", "saru", "chalse", "barabar", "ho", "hoy", "chalel", "nakki",
        "sounds", "good", "works", "see", "cya", "im", "i'm", "count", "course", "definitely", "confirmed", "booked",
    ]
    /// Allowed in a yes but not enough on their own.
    private static let agreementFillers: Set<String> = [
        "hai", "he", "che", "chhe", "for", "me", "you", "then", "in", "of", "ji", "it", "the", "to", "there", "that",
        "bhai", "bro", "bhaiya", "yaar", "yar", "dude", "man", "re", "ben", "bhau", "da", "buddy", "sir", "mam", "di",
        "didi", "boss", "dear", "na", "so", "very", "much", "thanks", "thank", "thx",
    ]
    private static let agreementEmoji: Set<Character> = ["👍", "👌", "🤝", "✅", "💯", "🙌", "👏"]

    /// Words that turn a reply into a no, a "maybe" or a question.
    private static let notAYes: Set<String> = [
        "not", "no", "nope", "can't", "cant", "cannot", "won't", "wont", "don't", "dont", "busy", "sorry", "cancel",
        "postpone", "reschedule", "maybe", "check", "confirm", "try", "nahi", "nahin", "nai", "mat", "nathi", "nako",
        "what", "when", "where", "which", "why", "how", "kya", "kab", "kaha", "kahan", "kitne", "kaun", "shu",
        "kyare", "kevi", "but", "lekin",
    ]
    private static let notAYesPhrases = ["let you know", "tell you", "get back", "will see", "dekhta", "dekhti", "batata",
                                         "batati", "bataunga", "bataungi", "sochta", "sochti", "another day", "next time",
                                         "some other", "kisi aur", "pachi kahu", "nantar sangto"]
    /// Words that say yes to a plan on their own, inside a longer reply.
    private static let planYesPhrases = ["milte hain", "milte hai", "milenge", "see you", "see ya", "ready", "confirmed",
                                         "chalega", "chalse", "thik hai", "theek hai", "done", "pakka", "malie", "bhetu"]

    /// Whether a reply says yes to a plan: a short yes ("ok", "okay bhai",
    /// "pakka", "haan chalo", "sounds good", "👍"), a yes that goes on to
    /// repeat the plan ("Done yaar, kal 6 baje coffee ke liye ready",
    /// "Perfect, kal 4pm pe milte hain"), or "kal 4pm pe milte hain". Anything
    /// with a no, a maybe or a question ("ok but not Friday", "okay I'll check") isn't.
    static func isAgreement(_ text: String) -> Bool {
        if isShortYes(text) { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 160, !trimmed.contains("?") else { return false }
        let lower = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        let words = lower.split(whereSeparator: { !($0.isLetter || $0 == "'") }).map(String.init)
        let padded = " " + words.joined(separator: " ") + " "
        guard !words.contains(where: notAYes.contains), !notAYesPhrases.contains(where: { padded.contains(" \($0) ") }) else { return false }
        // A yes up front, then anything: "Done yaar, ...", "Perfect, ...".
        if let first = lower.split(whereSeparator: { ",.!;:-–".contains($0) }).first, isShortYes(String(first)) { return true }
        return planYesPhrases.contains { padded.contains(" \($0) ") }
    }

    /// Just a short yes.
    private static func isShortYes(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        let lower = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        let words = lower.split(whereSeparator: { !($0.isLetter || $0 == "'") }).map(String.init)
        if words.isEmpty { return trimmed.contains(where: { agreementEmoji.contains($0) }) }
        guard words.count <= 6, words.allSatisfy({ agreementWords.contains($0) || agreementFillers.contains($0) }) else { return false }
        return words.contains { agreementWords.contains($0) }
    }

    /// Words that make a message a proposal rather than news.
    private static let proposalWords = [
        "let's", "lets", "let us", "shall we", "should we", "wanna", "want to", "how about", "what about", "can we",
        "could we", "are you free", "you free", "free on", "free at", "meet", "milte", "milna", "milo", "malie",
        "maliye", "bhetu", "bhetuya", "coffee", "lunch", "dinner", "breakfast", "drinks", "chai", "call", "catch up",
        "movie", "gym", "party", "game", "match", "chalo", "chal ", "join", "come", "aaja", "aa jana", "aavje",
    ]
    private static let activities: [(words: [String], title: String)] = [
        (["coffee", "coffe", "cofee", "cafe"], "Coffee"), (["chai", "tea"], "Chai"), (["breakfast", "nashta"], "Breakfast"),
        (["lunch"], "Lunch"), (["dinner", "khana"], "Dinner"), (["drinks", "beer", "beers"], "Drinks"),
        (["movie", "film", "picture"], "Movie"), (["gym", "workout", "run"], "Gym"),
        (["cricket", "football", "badminton", "game", "match"], "Game"), (["party"], "Party"),
        (["call", "phone"], "Call"), (["meeting"], "Meeting"),
        (["meet", "milte", "milna", "milo", "malie", "maliye", "bhetu", "bhetuya", "catch up"], "Meet"),
    ]

    /// The plan in an invitation answered with a yes, if it names a time.
    static func agreedPlan(invitation: String, reply: String, person: String, now: Date,
                           calendar: Calendar = .current) -> PromiseCandidate? {
        guard isAgreement(reply) else { return nil }
        let lower = " " + invitation.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        let words = Set(lower.split(whereSeparator: { !($0.isLetter || $0 == "'") }).map(String.init))
        let isProposal = invitation.contains("?") || proposalWords.contains { word in
            word.contains(" ") ? lower.contains(word) : words.contains(word)
        }
        guard isProposal else { return nil }
        // The time the reply says is the one agreed ("Perfect, kal 4pm pe milte hain").
        // A reply with only a time ("haan, par 6 baje") keeps the invitation's day.
        let dayWords = ["tomorrow", "today", "tonight", "in 2 days", "next week", "weekend"] + weekdays
        let replyEnglish = englishTimes(reply)
        let invitationDays = dayWords.filter { englishTimes(lower).contains($0) }
        let replyText = dayWords.contains(where: { replyEnglish.contains($0) }) ? replyEnglish
            : invitationDays.joined(separator: " ") + " " + replyEnglish
        let replySaysTime = (replyEnglish.contains(where: \.isNumber)
            || ["morning", "afternoon", "evening", "night", "tonight"].contains(where: replyEnglish.contains))
            && dueDate(in: " " + replyEnglish + " ", now: now, calendar: calendar).1
        let replyTime = replySaysTime ? dueDate(in: " " + replyText + " ", now: now, calendar: calendar) : (now, false)
        let (due, explicit) = replyTime.1 ? replyTime : dueDate(in: lower, now: now, calendar: calendar)
        guard explicit, due > now else { return nil }
        // What the plan is, from both messages ("coffe" in one, "coffee" in the other).
        let both = lower + " " + reply.lowercased() + " "
        let bothWords = Set(both.split(whereSeparator: { !($0.isLetter || $0 == "'") }).map(String.init))
        return PromiseCandidate(kind: .mine, title: planTitle(both, words: bothWords, person: person), due: due, hasExplicitTime: true)
    }

    /// "Coffee with Rahul", "Call Rahul", "Meet Rahul", or "Plan with Rahul".
    static func planTitle(_ lower: String, words: Set<String>, person: String) -> String {
        let name = firstName(person)
        let activity = activities.first { activity in
            activity.words.contains { $0.contains(" ") ? lower.contains($0) : words.contains($0) }
        }?.title
        switch activity {
        case "Meet"?: return name.isEmpty ? "Meet up" : "Meet \(name)"
        case "Call"?: return name.isEmpty ? "Call" : "Call \(name)"
        case let activity?: return name.isEmpty ? activity : "\(activity) with \(name)"
        case nil: return name.isEmpty ? "Plan" : "Plan with \(name)"
        }
    }
}
