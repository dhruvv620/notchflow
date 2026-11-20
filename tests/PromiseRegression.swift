// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct PromiseRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "PromiseRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = PromisePolicy
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Wednesday 18 November 2026, 2 pm.
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14))!
        try require(calendar.component(.weekday, from: now) == 4, "Test date is not a Wednesday")
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        func mine(_ text: String) -> PromiseCandidate? { P.detect(text, fromMe: true, now: now, calendar: calendar) }
        func show(_ c: PromiseCandidate?) -> String { c.map { "\($0.title) @ \($0.due)" } ?? "nil" }

        // Your promises, with titles and due times.
        var c = mine("I'll send the deck tonight")
        try require(c?.title == "Send the deck" && c?.due == at(18, 20) && c?.kind == .mine && c?.hasExplicitTime == true, "tonight: \(show(c))")
        c = mine("Let me check and get back to you")
        try require(c?.title == "Check and get back to you" && c?.hasExplicitTime == false && c?.due == now.addingTimeInterval(86_400), "check: \(show(c))")
        c = mine("Will review tomorrow")
        try require(c?.title == "Review" && c?.due == at(19, 10), "tomorrow: \(show(c))")
        c = mine("Sure, I'll call you at 5")
        try require(c?.title == "Call you" && c?.due == at(18, 17), "at 5: \(show(c))")
        c = mine("I'll get it done in 2 hours.")
        try require(c?.title == "Get it done" && c?.due == now.addingTimeInterval(7200), "in 2 hours: \(show(c))")
        c = mine("I'm going to push the fix later")
        try require(c?.title == "Push the fix" && c?.due == now.addingTimeInterval(3 * 3600), "later: \(show(c))")
        c = mine("I’ll share the notes next week")
        try require(c?.title == "Share the notes" && c?.due == at(23, 10), "next week (curly apostrophe): \(show(c))")
        c = mine("I'll be there at 7pm")
        try require(c?.title == "Be there" && c?.due == at(18, 19), "7pm: \(show(c))")
        c = mine("Will do, by tomorrow morning")
        try require(c?.title == "Follow up" && c?.due == at(19, 9), "will do + time: \(show(c))")
        c = mine("ok. I'll send it by Friday!")
        try require(c?.title == "Send it" && c?.due == at(20, 17), "by Friday: \(show(c))")
        c = mine("I will definitely finish the report by end of day")
        try require(c?.title == "Finish the report" && c?.due == at(18, 18), "end of day: \(show(c))")
        c = mine("I'll fix it tomorrow at 3pm")
        try require(c?.title == "Fix it" && c?.due == at(19, 15), "tomorrow at 3pm: \(show(c))")

        // Not promises.
        for text in ["Can you send it?", "Let me know when you're free", "Will you come tonight?", "I won't make it",
                     "will do", "On it", "I'll be honest, that was great", "Thanks!", "I will never do that again",
                     "Will it rain tomorrow", "See you at 5"] {
            try require(mine(text) == nil, "Not a promise but detected: \(text) -> \(show(mine(text)))")
        }

        // Promises made to you.
        c = P.detect("Thanks! I'll send you the invoice Monday.", fromMe: false, now: now, calendar: calendar)
        try require(c?.kind == .theirs && c?.title == "Send you the invoice" && c?.due == at(23, 17), "theirs: \(show(c))")
        try require(P.personalized(c!.title, kind: .theirs, person: "Alex Kim") == "Send me the invoice", "theirs personalized")
        try require(P.personalized("Send you the deck", kind: .mine, person: "Sam Patel") == "Send Sam the deck", "mine personalized")
        try require(P.personalized("Review your PR.", kind: .mine, person: "Sam") == "Review Sam's PR.", "possessive")
        try require(P.personalized("Call you", kind: .mine, person: "+1 555 0100") == "Call you", "phone number is not a name")

        // Nudges and drafts.
        let due = at(18, 20)
        try require(P.nudgeDate(due: due, lead: 3600, created: now) == at(18, 19), "Nudge an hour before")
        try require(P.nudgeDate(due: now.addingTimeInterval(600), lead: 3600, created: now) == now.addingTimeInterval(300), "Nudge not in the past")
        try require(P.followUpDraft(kind: .theirs, title: "Send me the invoice", person: "Alex Kim")
                    == "Hi Alex, just checking in on this (send me the invoice). Thanks!", "Their draft")
        try require(P.followUpDraft(kind: .mine, title: "Send Sam the deck", person: "Sam")
                    == "Sorry, running a bit behind on this (send Sam the deck). Is tomorrow morning okay?", "My draft")
        // Plans you said yes to. Today is Wednesday 18 November, 14:00.
        for yes in ["ok", "Okay bhai", "okk", "pakka", "haan chalo", "Sure!", "sounds good", "done bro", "👍", "thik che",
                    "ho nakki", "theek hai", "see you then"] {
            try require(P.isAgreement(yes), "Not a yes: \(yes)")
        }
        for notYes in ["ok but not friday", "can't, sorry", "no", "okay I'll check and tell you", "haha", "not sure",
                       "ok so what time does the movie start tomorrow evening"] {
            try require(!P.isAgreement(notYes), "Taken as a yes: \(notYes)")
        }
        let coffee = P.agreedPlan(invitation: "let's meet for coffee on Friday 5 p.m.", reply: "okay bhai", person: "Rahul Shah",
                                  now: now, calendar: calendar)
        try require(coffee?.title == "Coffee with Rahul" && coffee?.kind == .mine && coffee?.hasExplicitTime == true,
                    "Coffee plan: \(String(describing: coffee))")
        try require(coffee?.due == at(20, 17, 0), "Coffee due: \(String(describing: coffee?.due))")
        let call = P.agreedPlan(invitation: "Can we do a call tomorrow at 11am?", reply: "sure", person: "Priya", now: now, calendar: calendar)
        try require(call?.title == "Call Priya" && call?.due == at(19, 11, 0), "Call plan: \(String(describing: call))")
        let meet = P.agreedPlan(invitation: "milte hai saturday 7pm", reply: "haan", person: "+919800000000", now: now, calendar: calendar)
        try require(meet?.title == "Meet up" && meet?.due == at(21, 19, 0), "Meet plan: \(String(describing: meet))")
        try require(P.agreedPlan(invitation: "let's catch up sometime", reply: "ok", person: "Sam", now: now, calendar: calendar) == nil,
                    "A plan without a time kept")
        try require(P.agreedPlan(invitation: "I reached home at 5pm", reply: "ok", person: "Sam", now: now, calendar: calendar) == nil,
                    "News taken as a plan")
        try require(P.agreedPlan(invitation: "coffee Friday 5pm?", reply: "can't, sorry", person: "Sam", now: now, calendar: calendar) == nil,
                    "A no taken as a yes")
        print("Promises: OK")
    }
}
