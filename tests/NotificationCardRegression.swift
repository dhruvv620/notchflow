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
        try require(!NotificationCardPolicy.isCallCard(app: .whatsapp, texts: ["Group invitation"], buttonLabels: ["Accept", "Decline"]), "Invitation was incorrectly treated as a call")
        try require(NotificationCardPolicy.isCallCard(app: .faceTime, texts: ["Alex"], buttonLabels: ["Accept", "Decline"]), "Native incoming call was duplicated as notification")
        try require(NotificationCardPolicy.button("Reply…", matches: .reply) && !NotificationCardPolicy.button("Reply from Alex", matches: .reply), "Reply matching was too broad")
        let first = NotificationCardPolicy.stableID(app: .messages, nativeIdentity: "1", sender: "Alex", body: "Hello")
        let replacement = NotificationCardPolicy.stableID(app: .messages, nativeIdentity: "2", sender: "Alex", body: "Hello")
        try require(first != replacement, "Replacement card inherited stale reply identity")
        print("Notification card parsing, source filtering and action classification checks passed")
    }
}
