// SPDX-License-Identifier: GPL-3.0-or-later
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
        print("Notification card parsing, source filtering and action classification checks passed")
    }
}
