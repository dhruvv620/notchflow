// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct ParsedReminderInput: Equatable, Sendable {
    let title: String
    let dueDate: Date
    let includesTime: Bool
    let matchedText: String
}

/// A conservative, local English date parser. Only a complete trailing phrase is
/// removed from the title; uncertain input remains ordinary reminder text.
enum ReminderDateParser {
    private static let clock = #"(?:noon|midnight|\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)|\d{1,2}:\d{2})"#
    private static let weekdays = "sunday|monday|tuesday|wednesday|thursday|friday|saturday"
    private static let monthNames = "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"

    static func parse(_ input: String, referenceDate: Date = Date(), calendar: Calendar = .current) -> ParsedReminderInput? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.utf8.count <= 16_384 else { return nil }
        let startOfToday = calendar.startOfDay(for: referenceDate)

        if let match = suffix(#"in\s+(\d{1,5})\s+(minutes?|mins?|hours?|hrs?|days?|weeks?)(?:\s+at\s+("# + clock + "))?", in: input) {
            guard let amount = Int(match.group(2) ?? ""), (1...10_000).contains(amount),
                  let unit = match.group(3)?.lowercased() else { return nil }
            let time = match.group(4)
            let component: Calendar.Component
            let includesTime: Bool
            if unit.hasPrefix("min") { component = .minute; includesTime = true }
            else if unit.hasPrefix("h") { component = .hour; includesTime = true }
            else if unit.hasPrefix("day") { component = .day; includesTime = time != nil }
            else { component = .weekOfYear; includesTime = time != nil }
            if time != nil && (component == .minute || component == .hour) { return nil }
            guard var date = calendar.date(byAdding: component, value: amount, to: includesTime && time == nil ? referenceDate : startOfToday) else { return nil }
            if let time {
                guard let parts = clockParts(time), let timedDate = setTime(parts, on: date, calendar: calendar) else { return nil }
                date = timedDate
            }
            return result(match, date: date, includesTime: includesTime)
        }

        if let match = suffix("(today|tomorrow)(?:\\s+(?:at\\s+)?(" + clock + "))?", in: input) {
            let offset = match.group(2)?.lowercased() == "tomorrow" ? 1 : 0
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { return nil }
            return datedResult(match, day: day, time: match.group(3), calendar: calendar)
        }

        if let match = suffix("(next\\s+)?(" + weekdays + ")(?:\\s+(?:at\\s+)?(" + clock + "))?", in: input) {
            guard let weekday = match.group(3)?.lowercased(),
                  let index = weekdays.split(separator: "|").firstIndex(where: { $0 == weekday }) else { return nil }
            var offset = (index + 1 - calendar.component(.weekday, from: referenceDate) + 7) % 7
            if match.group(2) != nil && offset == 0 { offset = 7 }
            guard var day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { return nil }
            if offset == 0, let rawTime = match.group(4), let parts = clockParts(rawTime),
               let time = setTime(parts, on: day, calendar: calendar), time <= referenceDate {
                guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: day) else { return nil }
                day = nextWeek
            }
            return datedResult(match, day: day, time: match.group(4), calendar: calendar)
        }

        if let match = suffix(#"(\d{4})-(\d{2})-(\d{2})(?:\s+(?:at\s+)?("# + clock + "))?", in: input) {
            guard let year = Int(match.group(2) ?? ""), let month = Int(match.group(3) ?? ""), let day = Int(match.group(4) ?? ""),
                  let date = validDay(year: year, month: month, day: day, calendar: calendar) else { return nil }
            return datedResult(match, day: date, time: match.group(5), calendar: calendar)
        }

        if let match = suffix("(" + monthNames + #")\s+(\d{1,2})(?:,?\s+(\d{4}))?(?:\s+(?:at\s+)?("# + clock + "))?", in: input) {
            guard let name = match.group(2)?.lowercased(), let month = monthNumber(name), let day = Int(match.group(3) ?? "") else { return nil }
            let explicitYear = match.group(4).flatMap(Int.init)
            var year = explicitYear ?? calendar.component(.year, from: referenceDate)
            guard var date = validDay(year: year, month: month, day: day, calendar: calendar) else { return nil }
            if explicitYear == nil && date < startOfToday {
                year += 1
                guard let nextYear = validDay(year: year, month: month, day: day, calendar: calendar) else { return nil }
                date = nextYear
            }
            return datedResult(match, day: date, time: match.group(5), calendar: calendar)
        }

        // A time without a date means the next occurrence in the local calendar.
        // Bare numbers such as "7" are deliberately not treated as times.
        if let match = suffix(clock, in: input) {
            guard let parts = clockParts(match.group(1) ?? ""), var date = setTime(parts, on: startOfToday, calendar: calendar) else { return nil }
            if date <= referenceDate {
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
                      let next = setTime(parts, on: tomorrow, calendar: calendar) else { return nil }
                date = next
            }
            return result(match, date: date, includesTime: true)
        }
        return nil
    }

    private struct SuffixMatch {
        let title: String
        let input: String
        let match: NSTextCheckingResult
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: input) else { return nil }
            return String(input[range])
        }
    }

    private static func suffix(_ expression: String, in input: String) -> SuffixMatch? {
        let pattern = #"(?:^|\s)(?:(?:by|on|at)\s+)?("# + expression + #")\s*[.!]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range, in: input) else { return nil }
        let title = String(input[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.contains(where: { $0.isLetter || $0.isNumber }), !containsConflictingDate(title),
              title.range(of: #"\b(?:after|before|until|around|about|not)\s*$"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return SuffixMatch(title: title, input: input, match: match)
    }

    private static func containsConflictingDate(_ title: String) -> Bool {
        let pattern = #"\b(?:today|tomorrow|tonight|yesterday|utc|gmt|pst|pdt|mst|mdt|cst|cdt|est|edt|"# + weekdays + #")\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b|\bin\s+\d+\s+(?:minutes?|mins?|hours?|hrs?|days?|weeks?)\b|\b(?:"# + monthNames + #")\s+\d{1,2}\b|\b(?:noon|midnight|\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?))\b"#
        return title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func result(_ match: SuffixMatch, date: Date, includesTime: Bool) -> ParsedReminderInput? {
        guard let phrase = match.group(1) else { return nil }
        return ParsedReminderInput(title: match.title, dueDate: date, includesTime: includesTime, matchedText: phrase)
    }

    private static func datedResult(_ match: SuffixMatch, day: Date, time: String?, calendar: Calendar) -> ParsedReminderInput? {
        guard let time else { return result(match, date: calendar.startOfDay(for: day), includesTime: false) }
        guard let parts = clockParts(time), let date = setTime(parts, on: day, calendar: calendar) else { return nil }
        return result(match, date: date, includesTime: true)
    }

    private static func clockParts(_ input: String) -> (hour: Int, minute: Int)? {
        let text = input.lowercased().components(separatedBy: .whitespacesAndNewlines).joined().replacingOccurrences(of: ".", with: "")
        if text == "noon" { return (12, 0) }
        if text == "midnight" { return (0, 0) }
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text), var hour = Int(text[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        let period = Range(match.range(at: 3), in: text).map { String(text[$0]) }
        guard (0...59).contains(minute) else { return nil }
        if let period {
            guard (1...12).contains(hour) else { return nil }
            hour %= 12
            if period == "pm" { hour += 12 }
        } else {
            guard input.contains(":"), (0...23).contains(hour) else { return nil }
        }
        return (hour, minute)
    }

    private static func setTime(_ parts: (hour: Int, minute: Int), on day: Date, calendar: Calendar) -> Date? {
        guard let date = calendar.date(bySettingHour: parts.hour, minute: parts.minute, second: 0, of: day,
                                       matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward),
              calendar.isDate(date, inSameDayAs: day),
              calendar.component(.hour, from: date) == parts.hour,
              calendar.component(.minute, from: date) == parts.minute else { return nil }
        return date
    }

    private static func validDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func monthNumber(_ name: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return names.firstIndex(of: String(name.prefix(3))).map { $0 + 1 }
    }
}
