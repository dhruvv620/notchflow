// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import Foundation

@main
struct NotificationCardRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotificationCardRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let allowed: Set<CommunicationApp> = [.messages, .whatsapp]
        let parsed = NotificationCardPolicy.content(staticTexts: ["Messages", "now", "Alex", "Meet at 7?"], allowedApps: allowed)
        try require(parsed?.app == .messages && parsed?.sender == "Alex" && parsed?.body == "Meet at 7?", "Notification header leaked into body")
        try require(NotificationCardPolicy.content(staticTexts: ["Messages", "Alex", "Today"], allowedApps: allowed)?.body == "Today", "Date word in actual message was removed")
        try require(NotificationCardPolicy.content(staticTexts: ["Messages", "1m ago", "Alex", "WhatsApp", "is working"], allowedApps: allowed)?.app == .messages, "Body app name replaced notification source")
        try require(NotificationCardPolicy.content(staticTexts: ["Alex", "I use Messages"], allowedApps: allowed) == nil, "Arbitrary content was identified as a notification")
        try require(NotificationCardPolicy.content(staticTexts: ["Instagram", "Alex", "Hello"], allowedApps: allowed) == nil, "Disabled app was collected")
        try require(NotificationCardPolicy.content(staticTexts: ["Messages", "now"], allowedApps: allowed) == nil, "Hidden preview invented a sender/body")
        let modern = NotificationCardPolicy.content(
            identifiedTexts: [
                .init(identifier: "header", value: "Messages"),
                .init(identifier: "title", value: "Alex"),
                .init(identifier: "body", value: "Meet at 7?"),
            ],
            flattenedDescription: "Messages, Alex, Meet at 7?",
            imageLabels: [],
            allowedApps: allowed
        )
        try require(modern?.app == .messages && modern?.sender == "Alex" && modern?.body == "Meet at 7?",
                    "Modern identified Notification Center fields were not parsed")
        let described = NotificationCardPolicy.content(
            identifiedTexts: [
                .init(identifier: "title", value: "Alex"),
                .init(identifier: "subtitle", value: "Messages"),
                .init(identifier: "body", value: "WhatsApp is working"),
            ],
            flattenedDescription: "Messages, Alex, Messages, WhatsApp is working",
            imageLabels: [],
            allowedApps: allowed
        )
        try require(described?.app == .messages && described?.body == "WhatsApp is working",
                    "Exact description prefix did not recover the source safely")
        try require(NotificationCardPolicy.content(
            identifiedTexts: [.init(identifier: "title", value: "Alex"), .init(identifier: "body", value: "I use Messages")],
            flattenedDescription: "Alex, I use Messages", imageLabels: [], allowedApps: allowed
        ) == nil, "Message content was incorrectly used as a source label")
        try require(NotificationCardPolicy.content(
            identifiedTexts: [
                .init(identifier: "header", value: "Messages"), .init(identifier: "title", value: "Alex"),
                .init(identifier: "title", value: "Sam"), .init(identifier: "body", value: "Stacked"),
            ], flattenedDescription: nil, imageLabels: [], allowedApps: allowed
        ) == nil, "A multi-card stack was flattened into one notification")
        try require(NotificationCardPolicy.content(
            identifiedTexts: [
                .init(identifier: "", value: "Messages"), .init(identifier: "", value: "Alex"),
                .init(identifier: "", value: "Hello"),
            ], flattenedDescription: nil, imageLabels: ["Messages"], allowedApps: allowed
        ) == nil, "An app-first legacy card was misread as an anonymous modern card")
        try require(NotificationCardPolicy.content(
            identifiedTexts: [
                .init(identifier: "header", value: "Messages"), .init(identifier: "title", value: "Alex"),
                .init(identifier: "body", value: "Hello"),
            ], flattenedDescription: "Messages, Alex, Hello", imageLabels: ["WhatsApp"], allowedApps: allowed
        ) == nil, "Conflicting source evidence was accepted")
        try require(NotificationCardPolicy.content(
            identifiedTexts: [
                .init(identifier: "header", value: "Messages"), .init(identifier: "title", value: "Alex"),
                .init(identifier: "body", value: "Hello"),
            ], flattenedDescription: "Messages, Alex, Hello", imageLabels: ["WhatsApp"],
            legacyStaticTexts: ["Messages", "Alex", "Hello"], allowedApps: allowed
        ) == nil, "Legacy parsing bypassed conflicting semantic source evidence")
        try require(NotificationCardPolicy.app(named: "\u{200E}Messages\u{200F}") == .messages,
                    "Direction marks in a localized app label prevented source matching")
        try require(NotificationCardPolicy.isNotificationContainer(subrole: "AXNotificationCenterAlert")
                    && NotificationCardPolicy.isNotificationContainer(subrole: "AXNotificationCenterBannerStack")
                    && !NotificationCardPolicy.isNotificationContainer(subrole: "AXGroup"),
                    "Notification Center banner/alert subroles were not classified")
        try require(!NotificationCardPolicy.isCallCard(app: .whatsapp, texts: ["Group invitation"], buttonLabels: ["Accept", "Decline"]), "Invitation was incorrectly treated as a call")
        try require(NotificationCardPolicy.isCallCard(app: .faceTime, texts: ["Alex"], buttonLabels: ["Accept", "Decline"]), "Native incoming call was duplicated as notification")
        try require(NotificationCardPolicy.button("Reply…", matches: .reply) && !NotificationCardPolicy.button("Reply from Alex", matches: .reply), "Reply matching was too broad")
        let first = NotificationCardPolicy.stableID(app: .messages, nativeIdentity: "1", sender: "Alex", body: "Hello")
        let replacement = NotificationCardPolicy.stableID(app: .messages, nativeIdentity: "2", sender: "Alex", body: "Hello")
        try require(first != replacement, "Replacement card inherited stale reply identity")
        let waiting = NotificationBridgeDiagnostics(state: .waitingForBanner, processCount: 1, windowCount: 0,
                                                    candidateCount: 0, recognizedCount: 0)
        try require(waiting.message.contains("waiting"), "Empty inbox diagnostics did not explain the rendered-banner requirement")
        // Old cards in the open Notification Center panel are not new arrivals.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14, minute: 0))!
        let card = NotificationCardPolicy.Content(app: .messages, sender: "Alex", body: "See you at 10:30")
        func age(_ texts: [String]) -> TimeInterval? { NotificationCardPolicy.shownAge(texts: texts, excluding: card, now: now, calendar: calendar) }
        try require(age(["Messages", "now", "Alex", "See you at 10:30"]) == 0, "\"now\" is not new")
        try require(age(["Messages", "5m ago", "Alex", "See you at 10:30"]) == 300, "5m ago")
        try require(age(["Messages", "2h", "Alex"]) == 7_200 && age(["1 hour ago"]) == 3_600 && age(["Yesterday"]) == 86_400, "Hours and days")
        try require(age(["Messages", "13:15", "Alex"]) == 2_700 && age(["1:15 PM"]) == 2_700, "Clock time")
        try require(age(["Messages", "Alex", "See you at 10:30"]) == nil, "Time in the message read as the card's time")
        try require(age(["Messages", "18:00"]) == 20 * 3600, "A later clock time is yesterday")
        typealias C = NotificationCardPolicy
        try require(!C.isBrowsedInPanel(shownAge: 0, pointerOnCard: false, newCardsInScan: 1), "A new banner treated as old")
        try require(!C.isBrowsedInPanel(shownAge: nil, pointerOnCard: false, newCardsInScan: 2), "Two banners treated as the panel")
        try require(C.isBrowsedInPanel(shownAge: nil, pointerOnCard: true, newCardsInScan: 1), "Hovered card announced")
        try require(C.isBrowsedInPanel(shownAge: 600, pointerOnCard: false, newCardsInScan: 1), "Ten-minute-old card announced")
        try require(C.isBrowsedInPanel(shownAge: nil, pointerOnCard: false, newCardsInScan: 4), "Opening the panel announced its cards")
        print("Notification card parsing, source filtering and action classification checks passed")
    }
}
