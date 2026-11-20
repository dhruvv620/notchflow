// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct NotificationHubRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotificationHubRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func item(_ id: String, app: String?, name: String = "App", title: String = "", body: String, at seconds: TimeInterval,
                  source: NotchNotification.Source = .notificationCenter) -> NotchNotification {
            NotchNotification(id: id, source: source, bundleIdentifier: app, appName: name, title: title, subtitle: "",
                              body: body, date: Date(timeIntervalSince1970: seconds), threadID: nil, reply: .none, liveBannerID: nil)
        }

        // Notification Center records are binary property lists.
        let plist: [String: Any] = [
            "app": "com.apple.MobileSMS",
            "date": 790_000_000.0,
            "req": ["titl": "Selene", "subt": "", "body": "Are you coming?", "thre": "iMessage;-;+15551234567"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        guard let record = NotificationCenterRecord.parse(recordID: 42, appIdentifier: nil, data: data, fallbackDate: nil) else {
            throw NSError(domain: "NotificationHubRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: "Record not parsed"])
        }
        try require(record.bundleIdentifier == "com.apple.MobileSMS" && record.title == "Selene" && record.body == "Are you coming?", "Record fields misread")
        try require(record.date == Date(timeIntervalSinceReferenceDate: 790_000_000), "Record date misread")
        let converted = record.notification(appName: "Messages")
        try require(converted.reply == .messages(chatID: "iMessage;-;+15551234567"), "Messages reply route not found")
        try require(converted.id.hasPrefix("nc-42-"), "Record id not stable")

        let fallbackPlist: [String: Any] = ["req": ["titl": "Build finished"]]
        let fallbackData = try PropertyListSerialization.data(fromPropertyList: fallbackPlist, format: .binary, options: 0)
        let fallback = NotificationCenterRecord.parse(recordID: 7, appIdentifier: "com.apple.dt.Xcode", data: fallbackData,
                                                      fallbackDate: Date(timeIntervalSinceReferenceDate: 5))
        try require(fallback?.bundleIdentifier == "com.apple.dt.Xcode" && fallback?.date == Date(timeIntervalSinceReferenceDate: 5), "App table and row date not used as fallbacks")
        try require(fallback?.notification(appName: "Xcode").reply == NotchNotification.ReplyRoute.none, "Reply offered for an app that cannot take one")
        let emptyPlist = try PropertyListSerialization.data(fromPropertyList: ["app": "x.y", "req": [String: Any]()], format: .binary, options: 0)
        try require(NotificationCenterRecord.parse(recordID: 1, appIdentifier: nil, data: emptyPlist, fallbackDate: nil) == nil, "Empty notification accepted")
        try require(NotificationCenterRecord.parse(recordID: 1, appIdentifier: nil, data: Data("junk".utf8), fallbackDate: nil) == nil, "Garbage accepted")

        // Messages chat identifiers
        try require(NotchNotificationPolicy.messagesChatID(fromThread: "SMS;+;chat123456") == "SMS;+;chat123456", "Group chat id rejected")
        try require(NotchNotificationPolicy.messagesChatID(fromThread: "random-thread") == nil, "Arbitrary thread treated as a chat")
        try require(NotchNotificationPolicy.messagesChatID(fromThread: "iMessage;-;") == nil, "Empty chat id accepted")

        // AppleScript strings cannot be broken out of.
        try require(NotchNotificationPolicy.appleScriptString(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#, "AppleScript string not escaped")
        let script = NotchNotificationPolicy.messagesReplyScript(text: "ok\" & do shell script \"x", chatID: "iMessage;-;+1")
        try require(script.contains(#"send "ok\" & do shell script \"x" to chat id "iMessage;-;+1""#), "Reply text escaped incorrectly")

        // Ordering, duplicates and limits
        let a = item("a", app: "com.a", body: "1", at: 10)
        let b = item("b", app: "com.b", body: "2", at: 30)
        let c = item("c", app: "com.a", body: "3", at: 20)
        let normalized = NotchNotificationPolicy.normalized([a, b, c, a], limit: 2)
        try require(normalized.map(\.id) == ["b", "c"], "Inbox not newest-first, deduplicated and limited")

        // Grouping by app, newest group first
        let groups = NotchNotificationPolicy.grouped([a, b, c])
        try require(groups.map(\.id) == ["com.b", "com.a"], "Groups not ordered by newest item")
        try require(groups.last?.items.map(\.id) == ["c", "a"], "Items inside a group not newest-first")

        // A banner and its Notification Center record are one notification.
        let stored = item("nc-1", app: "com.apple.MobileSMS", name: "Messages", title: "Selene", body: "Are you coming? I saved you a seat", at: 100)
        let banner = item("banner-x", app: "com.apple.MobileSMS", name: "Messages", title: "Selene", body: "Are you coming?", at: 103, source: .banner)
        try require(NotchNotificationPolicy.isSameNotification(banner, as: stored), "Banner not matched to its stored notification")
        let late = item("banner-y", app: "com.apple.MobileSMS", name: "Messages", title: "Selene", body: "Are you coming?", at: 400, source: .banner)
        try require(!NotchNotificationPolicy.isSameNotification(late, as: stored), "Banners minutes apart merged")
        let other = item("banner-z", app: "com.apple.MobileSMS", name: "Messages", title: "Khushii", body: "Are you coming?", at: 101, source: .banner)
        try require(!NotchNotificationPolicy.isSameNotification(other, as: stored), "Different senders merged")
        // The WhatsApp app on this Mac and the linked account: the same message once, other messages always.
        let gateway = NotchNotification(id: "wa-1", source: .whatsapp, bundleIdentifier: "net.whatsapp.WhatsApp", appName: "WhatsApp",
                                        title: "Riya · Family", subtitle: "", body: "Running 10 minutes late", date: Date(timeIntervalSince1970: 500),
                                        threadID: nil, reply: .none, liveBannerID: nil)
        let macApp = item("nc-2", app: "net.whatsapp.WhatsApp", name: "WhatsApp", title: "Family", body: "Riya: Running 10 minutes late", at: 503)
        try require(NotchNotificationPolicy.isSameWhatsAppMessage(macApp, gateway) && NotchNotificationPolicy.isSameWhatsAppMessage(gateway, macApp),
                    "Same WhatsApp message not merged")
        let personal = item("nc-3", app: "net.whatsapp.WhatsApp", name: "WhatsApp", title: "Mom", body: "Call me when free", at: 502)
        try require(!NotchNotificationPolicy.isSameWhatsAppMessage(personal, gateway), "Another account's message merged")
        let shortReply = item("nc-4", app: "net.whatsapp.WhatsApp", name: "WhatsApp", title: "Sam", body: "late", at: 501)
        try require(!NotchNotificationPolicy.isSameWhatsAppMessage(shortReply, gateway), "A short word matched inside another message")
        let hourLater = item("nc-5", app: "net.whatsapp.WhatsApp", name: "WhatsApp", title: "Family", body: "Running 10 minutes late", at: 4_000)
        try require(!NotchNotificationPolicy.isSameWhatsAppMessage(hourLater, gateway), "Messages an hour apart merged")
        try require(!NotchNotificationPolicy.isSameWhatsAppMessage(macApp, stored), "Messages app treated as WhatsApp")

        // The WhatsApp app's two identifiers are one app.
        let oldID = item("banner-v", app: "desktop.WhatsApp", name: "WhatsApp", title: "Mom", body: "Call me when free", at: 503, source: .banner)
        try require(NotchNotificationPolicy.isSameNotification(oldID, as: personal), "WhatsApp identifiers not treated as one app")
        // Replying through the WhatsApp app needs the chat's number.
        typealias N = NotchNotificationPolicy
        try require(N.whatsAppPhone(fromThread: "919876543210@s.whatsapp.net") == "919876543210", "JID thread")
        try require(N.whatsAppPhone(fromThread: "919876543210:12@s.whatsapp.net") == "919876543210", "Device JID thread")
        try require(N.whatsAppPhone(fromThread: "+91 98765 43210") == "919876543210", "Number thread")
        try require(N.whatsAppPhone(fromThread: "120363025246125244@g.us") == nil && N.whatsAppPhone(fromThread: "chat-42") == nil
                    && N.whatsAppPhone(fromThread: nil) == nil, "Group or unknown thread gave a number")
        try require(N.whatsAppSendURL(phone: "919876543210", text: "ok bhai, 5 baje")?.absoluteString
                    == "whatsapp://send?phone=919876543210&text=ok%20bhai,%205%20baje", "Send URL: \(N.whatsAppSendURL(phone: "919876543210", text: "ok bhai, 5 baje")?.absoluteString ?? "nil")")
        try require(N.whatsAppSendURL(phone: "1", text: "2+2 & more")?.absoluteString == "whatsapp://send?phone=1&text=2%2B2%20%26%20more",
                    "Plus or ampersand not escaped")
        try require(N.lastingReplyRoute(bundleIdentifier: "net.whatsapp.WhatsApp", threadID: "919876543210@s.whatsapp.net")
                    == .whatsappApp(phone: "919876543210"), "WhatsApp route")
        try require(N.lastingReplyRoute(bundleIdentifier: "com.apple.MobileSMS", threadID: "iMessage;-;+15551234567")
                    == .messages(chatID: "iMessage;-;+15551234567"), "Messages route")
        try require(N.lastingReplyRoute(bundleIdentifier: "com.tinyspeck.slackmacgap", threadID: "919876543210@s.whatsapp.net") == .none, "Slack route")

        // An old notification hovered in the open Notification Center panel, an hour later.
        let browsed = item("banner-w", app: "com.apple.MobileSMS", name: "Messages", title: "Selene", body: "Are you coming?", at: 3_700, source: .banner)
        try require(NotchNotificationPolicy.isSameNotification(browsed, as: stored, window: .infinity), "Panel card not matched to its notification")
        try require(!NotchNotificationPolicy.isSameNotification(other, as: stored, window: .infinity), "Panel card matched another sender")

        // The stored inbox survives a relaunch.
        let encoded = try JSONEncoder().encode([converted, stored])
        let decoded = try JSONDecoder().decode([NotchNotification].self, from: encoded)
        try require(decoded == [converted, stored], "Inbox does not round-trip through JSON")

        print("Notification inbox checks passed")
    }
}
