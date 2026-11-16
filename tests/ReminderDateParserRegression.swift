// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct ReminderDateParserRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "ReminderDateParserRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Phoenix")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15, minute: 30))!
        func parse(_ text: String) -> ParsedReminderInput? {
            ReminderDateParser.parse(text, referenceDate: now, calendar: calendar)
        }
        func components(_ value: ParsedReminderInput?) -> DateComponents? {
            value.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0.dueDate) }
        }

        let tomorrow = parse("Send invoice by tomorrow 7 pm")
        try require(tomorrow?.title == "Send invoice" && tomorrow?.matchedText == "tomorrow 7 pm", "Trailing date connector/title was not separated")
        try require(components(tomorrow)?.day == 13 && components(tomorrow)?.hour == 19 && tomorrow?.includesTime == true, "Tomorrow 7 pm was not tomorrow evening locally")
        let sentence = parse("I want to get it done by tomorrow 7 pm")
        try require(sentence?.title == "I want to get it done", "Natural reminder sentence lost its title")
        let today = parse("Review notes today")
        try require(components(today)?.day == 12 && components(today)?.hour == 0 && today?.includesTime == false, "Today acquired a time")
        try require(components(parse("Call dentist today at 7 am"))?.hour == 7, "Explicit today should not silently roll a past time forward")
        try require(components(parse("Lunch tomorrow at noon"))?.hour == 12, "Noon was not 12 PM")
        try require(components(parse("Deploy tomorrow at midnight"))?.hour == 0, "Midnight was not 12 AM")
        try require(components(parse("Call at 7 am"))?.day == 13, "Elapsed time-only input did not roll to tomorrow")
        try require(components(parse("Call 7 pm"))?.day == 12, "Future time-only input unexpectedly rolled a day")
        try require(components(parse("Call at 12 a.m."))?.hour == 0, "Dotted AM was not parsed")
        try require(components(parse("Call at 12 pm"))?.hour == 12, "12 PM became midnight")
        try require(components(parse("Call tomorrow 23:45"))?.hour == 23, "24-hour time was not parsed")
        try require(parse("Submit in 30 minutes")?.dueDate == calendar.date(byAdding: .minute, value: 30, to: now), "Relative minutes were not elapsed from reference")
        try require(components(parse("Submit in 2 days"))?.day == 14 && parse("Submit in 2 days")?.includesTime == false, "Relative days were not all-day")
        try require(components(parse("Submit in 2 days at 8 pm"))?.hour == 20, "Relative day plus time failed")
        try require(components(parse("Review friday at 9 am"))?.day == 13, "Weekday did not use nearest future occurrence")
        try require(components(parse("Review next thursday at 9 am"))?.day == 19, "Next same weekday did not advance one week")
        try require(components(parse("Submit on 2026-12-01 at 8:15 am"))?.month == 12, "Explicit ISO date failed")
        try require(components(parse("Submit November 15 at 8 pm"))?.day == 15, "English month date failed")
        try require(components(parse("Submit Jan 1"))?.year == 2027, "Unqualified month date in the past did not advance year")
        try require(parse("Call tomorrow")?.title == "Call", "Date-only tomorrow missing")
        try require(components(parse("CALL TOMORROW 7 PM"))?.hour == 19, "Date keywords must be case insensitive")
        try require(components(parse("Call tomorrow at 7\tpm"))?.hour == 19, "Pasted whitespace broke a supported time")
        try require(components(parse("Submit 2028-02-29"))?.day == 29, "Valid leap day was rejected")
        for input in ["Tomorrow 7 pm", "Call at 7", "Call tomorrow at 25pm", "Call tomorrow at 13 am", "Call tomorrow 23:99", "Call today tomorrow 7 pm", "Call after tomorrow 7 pm", "Call not tomorrow", "Call PST tomorrow 7 pm", "Call 4/5", "Call 4/5 at 7pm", "Call in 2 hours at 7pm", "Call 2026-02-30", "Call 2026-13-02", "Call tomorrow afternoon", "Just plain reminder text"] {
            try require(parse(input) == nil, "Ambiguous/invalid input was parsed: \(input)")
        }
        var dst = calendar
        dst.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = dst.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 12))!
        try require(ReminderDateParser.parse("Call tomorrow at 2:30 am", referenceDate: spring, calendar: dst) == nil, "Nonexistent DST time was silently shifted")
        let allDay = ReminderDateParser.parse("Call tomorrow", referenceDate: spring, calendar: dst)
        try require(allDay?.includesTime == false && allDay.map { dst.component(.day, from: $0.dueDate) } == 14, "DST changed the requested all-day date")
        let fall = dst.date(from: DateComponents(year: 2027, month: 11, day: 6, hour: 12))!
        let repeated = ReminderDateParser.parse("Call tomorrow at 1:30 am", referenceDate: fall, calendar: dst)
        try require(repeated != nil && repeated.map { dst.component(.hour, from: $0.dueDate) } == 1, "Repeated DST hour could not be scheduled")
        try require(repeated.map { dst.timeZone.secondsFromGMT(for: $0.dueDate) } == -7 * 60 * 60, "Repeated DST hour did not choose the first occurrence")
        print("Natural reminder date parser checks passed")
    }
}
