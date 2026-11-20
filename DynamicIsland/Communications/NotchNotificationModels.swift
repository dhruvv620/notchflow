// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import Foundation

/// One notification in the notch inbox, whatever it came from.
///
/// Pure value types and policy only (Foundation, no UI or system access), so
/// Build.command can check them with `swiftc` on its own.
struct NotchNotification: Identifiable, Equatable, Codable, Sendable {
    enum Source: String, Codable, Sendable {
        /// macOS Notification Center's own store (needs Full Disk Access).
        case notificationCenter
        /// A banner read from the screen through Accessibility.
        case banner
        /// A message from the linked WhatsApp gateway.
        case whatsapp
    }

    /// How a reply typed in the notch reaches the conversation.
    enum ReplyRoute: Equatable, Codable, Sendable {
        case none
        case whatsapp(chatJID: String)
        case messages(chatID: String)
        /// The live banner's own reply field. Only works while it is on screen.
        case banner(id: String)
        /// The WhatsApp app on this Mac, opened at the chat with this number.
        case whatsappApp(phone: String)

        var isAvailable: Bool { self != .none }
    }

    let id: String
    let source: Source
    /// Bundle identifier of the app that posted it, when known.
    var bundleIdentifier: String?
    var appName: String
    var title: String
    var subtitle: String
    var body: String
    var date: Date
    var threadID: String?
    var reply: ReplyRoute
    /// The matching on-screen banner, which can still be opened or dismissed.
    var liveBannerID: String?

    /// Groups notifications from the same app together.
    var groupKey: String { bundleIdentifier ?? "name:" + appName.lowercased() }

    /// The headline: the sender or title, falling back to the app.
    var headline: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
}

struct NotchNotificationGroup: Identifiable, Equatable, Sendable {
    let id: String
    let appName: String
    let bundleIdentifier: String?
    var items: [NotchNotification]

    var latest: Date { items.first?.date ?? .distantPast }
}

enum NotchNotificationPolicy {
    /// Most recent first, at most `limit`, no duplicate ids.
    static func normalized(_ items: [NotchNotification], limit: Int) -> [NotchNotification] {
        var seen = Set<String>()
        return Array(items
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
            .prefix(max(0, limit)))
    }

    /// Groups by app, newest group first, items newest first inside each group.
    static func grouped(_ items: [NotchNotification]) -> [NotchNotificationGroup] {
        var order: [String] = []
        var groups: [String: NotchNotificationGroup] = [:]
        for item in items.sorted(by: { $0.date > $1.date }) {
            let key = item.groupKey
            if groups[key] == nil {
                order.append(key)
                groups[key] = NotchNotificationGroup(id: key, appName: item.appName, bundleIdentifier: item.bundleIdentifier, items: [])
            }
            groups[key]?.items.append(item)
        }
        return order.compactMap { groups[$0] }
    }

    /// Whether two banners read from the screen are the same notification
    /// seen again: macOS can hand the reader a new element (and so a new id)
    /// for the same card between reads.
    static func isSameBanner(_ banner: NotchNotification, as existing: NotchNotification, window: TimeInterval = 600) -> Bool {
        guard banner.id != existing.id, banner.source == .banner, existing.source == .banner,
              banner.bundleIdentifier == existing.bundleIdentifier || banner.appName == existing.appName,
              abs(banner.date.timeIntervalSince(existing.date)) < window else { return false }
        func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return clean(banner.title) == clean(existing.title) && clean(banner.body) == clean(existing.body) && !clean(banner.body).isEmpty
    }

    /// The chat a reply route points at ("messages:iMessage;-;+1555…",
    /// "whatsapp:9198…@s.whatsapp.net", "whatsapp:9198…" for the Mac app).
    static func chatKey(_ route: NotchNotification.ReplyRoute) -> String? {
        switch route {
        case .messages(let chat):
            // "iMessage;-;+1555…", "SMS;-;+1555…" and "any;-;+1555…" are one chat.
            let parts = chat.lowercased().split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            return "messages:" + (parts.count == 2 ? String(parts[1]) : chat.lowercased())
        case .whatsapp(let jid): return "whatsapp:" + (jid.split(separator: "@").first.map(String.init) ?? jid)
        case .whatsappApp(let phone): return "whatsapp:" + phone
        case .banner, .none: return nil
        }
    }

    /// Whether two notifications belong to the same conversation: the same
    /// chat when both name one, otherwise the same app and sender.
    static func isSameConversation(_ lhs: NotchNotification, _ rhs: NotchNotification) -> Bool {
        if lhs.id == rhs.id { return true }
        func app(_ item: NotchNotification) -> String {
            if let id = item.bundleIdentifier, whatsAppBundleIdentifiers.contains(id) { return "whatsapp" }
            return item.groupKey
        }
        guard app(lhs) == app(rhs) else { return false }
        if let left = chatKey(lhs.reply), let right = chatKey(rhs.reply) { return left == right }
        if let left = lhs.threadID, let right = rhs.threadID, !left.isEmpty, !right.isEmpty { return left == right }
        func person(_ item: NotchNotification) -> String { item.headline.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return !person(lhs).isEmpty && person(lhs) == person(rhs)
    }

    /// A key for "this was just announced", so the same message isn't announced twice.
    static func announcementKey(_ item: NotchNotification) -> String {
        [item.bundleIdentifier ?? item.appName, item.title, item.body]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{1f}")
    }

    /// Whether a banner is a notification already in the inbox: same app,
    /// title and text, within `window` seconds (the store and the banner
    /// reader date the same notification slightly differently). Cards seen
    /// in the open Notification Center panel pass `.infinity`, since their
    /// time on screen says nothing about when they arrived.
    static func isSameNotification(_ banner: NotchNotification, as existing: NotchNotification,
                                   window: TimeInterval = 90) -> Bool {
        guard existing.id != banner.id, existing.source != .banner else { return false }
        let sameApp: Bool
        if let lhs = banner.bundleIdentifier, let rhs = existing.bundleIdentifier {
            // The WhatsApp app has had two identifiers; the banner reader may name the other one.
            sameApp = lhs == rhs || (whatsAppBundleIdentifiers.contains(lhs) && whatsAppBundleIdentifiers.contains(rhs))
        } else {
            sameApp = banner.appName.caseInsensitiveCompare(existing.appName) == .orderedSame
        }
        guard sameApp, abs(banner.date.timeIntervalSince(existing.date)) < window else { return false }
        func clean(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let body = clean(banner.body)
        guard !body.isEmpty else { return false }
        let existingBody = clean(existing.body)
        let bodyMatches = existingBody == body || existingBody.hasPrefix(body) || body.hasPrefix(existingBody)
        let title = clean(banner.title)
        let titleMatches = title.isEmpty || clean(existing.title) == title || clean(existing.subtitle) == title
        return bodyMatches && titleMatches
    }

    /// Messages posts its notifications with the conversation's identifier as
    /// the thread, e.g. `iMessage;-;+15551234567` or `SMS;+;chat1234`. That is
    /// the `id` AppleScript accepts for `chat id "…"`.
    static func messagesChatID(fromThread thread: String?) -> String? {
        guard let thread = thread?.trimmingCharacters(in: .whitespacesAndNewlines), !thread.isEmpty else { return nil }
        let parts = thread.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              ["imessage", "sms", "rcs", "any"].contains(parts[0].lowercased()),
              parts[1] == "-" || parts[1] == "+",
              !parts[2].isEmpty else { return nil }
        return thread
    }

    static let messagesBundleIdentifier = "com.apple.MobileSMS"
    static let whatsAppBundleIdentifiers: Set<String> = ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]

    /// The phone number of a WhatsApp chat from a notification's thread
    /// ("919876543210@s.whatsapp.net", "+91 98765 43210"); nil for groups and
    /// for private ids ("49752934731960@lid"), which look like numbers but aren't.
    static func whatsAppPhone(fromThread thread: String?) -> String? {
        guard let thread = thread?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !thread.isEmpty else { return nil }
        if let at = thread.firstIndex(of: "@") {
            let domain = thread[thread.index(after: at)...]
            guard domain == "s.whatsapp.net" || domain == "c.us" else { return nil }
        }
        let local = thread.split(separator: "@").first.map(String.init) ?? thread
        let candidate = local.split(separator: ":").first.map(String.init) ?? local
        guard candidate.allSatisfy({ $0.isNumber || "+ -()".contains($0) }) else { return nil }
        return whatsAppPhone(fromNumber: candidate)
    }

    /// Digits WhatsApp's click-to-chat link accepts (country code, no +).
    static func whatsAppPhone(fromNumber number: String) -> String? {
        let digits = number.filter(\.isNumber)
        return (8...15).contains(digits.count) ? digits : nil
    }

    /// How to reply once a live banner is gone: Messages by its chat, the
    /// WhatsApp app by the chat's number, otherwise not from the notch.
    static func lastingReplyRoute(bundleIdentifier: String?, threadID: String?) -> NotchNotification.ReplyRoute {
        if bundleIdentifier == messagesBundleIdentifier, let chat = messagesChatID(fromThread: threadID) { return .messages(chatID: chat) }
        if let bundleIdentifier, whatsAppBundleIdentifiers.contains(bundleIdentifier),
           let phone = whatsAppPhone(fromThread: threadID) { return .whatsappApp(phone: phone) }
        return .none
    }

    /// Opens the WhatsApp app at the chat with the text typed in.
    static func whatsAppSendURL(phone: String, text: String) -> URL? {
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "text", value: text)]
        // A "+" left as is would arrive as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Whether a notification from the WhatsApp app on this Mac and a message
    /// from the linked WhatsApp account are the same message (when both are
    /// the same account). They name the chat differently (contact name vs.
    /// push name, "Sam: hi" in groups), so only the text and time are compared.
    /// The Mac app may be another account than the linked one (personal vs.
    /// business): its other messages must still come through.
    static func isSameWhatsAppMessage(_ lhs: NotchNotification, _ rhs: NotchNotification) -> Bool {
        guard lhs.source != rhs.source, lhs.source == .whatsapp || rhs.source == .whatsapp,
              let left = lhs.bundleIdentifier, let right = rhs.bundleIdentifier,
              whatsAppBundleIdentifiers.contains(left), whatsAppBundleIdentifiers.contains(right),
              abs(lhs.date.timeIntervalSince(rhs.date)) < 180 else { return false }
        func clean(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let a = clean(lhs.body), b = clean(rhs.body)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
        // "Sam: running late" in a group notification is "running late" from the gateway.
        return shorter.count >= 6 && (longer.hasSuffix(shorter) || longer.hasPrefix(shorter))
    }

    /// Escapes text for a double-quoted AppleScript string literal.
    static func appleScriptString(_ value: String) -> String {
        var result = "\""
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            default: result.append(character)
            }
        }
        return result + "\""
    }

    static func messagesReplyScript(text: String, chatID: String) -> String {
        """
        tell application "Messages"
            send \(appleScriptString(text)) to chat id \(appleScriptString(chatID))
        end tell
        """
    }
}

/// One row of Notification Center's store, decoded from its binary plist.
///
/// macOS keeps delivered notifications in an SQLite database whose `record`
/// table holds each notification as a property list: the posting app under
/// `app`, the delivery time under `date` (seconds since 2001), and the request
/// under `req` with `titl`, `subt`, `body` and the thread under `thre`.
struct NotificationCenterRecord: Equatable, Sendable {
    let recordID: Int64
    let bundleIdentifier: String
    let title: String
    let subtitle: String
    let body: String
    let threadID: String?
    let date: Date

    static func parse(recordID: Int64, appIdentifier: String?, data: Data, fallbackDate: Date?) -> NotificationCenterRecord? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any] else { return nil }
        let request = root["req"] as? [String: Any] ?? [:]

        func string(_ dictionary: [String: Any], _ key: String) -> String {
            (dictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func date(_ value: Any?) -> Date? {
            if let date = value as? Date { return date }
            if let seconds = value as? Double { return Date(timeIntervalSinceReferenceDate: seconds) }
            if let number = value as? NSNumber { return Date(timeIntervalSinceReferenceDate: number.doubleValue) }
            return nil
        }

        let bundle = (root["app"] as? String) ?? appIdentifier ?? ""
        let title = string(request, "titl")
        let subtitle = string(request, "subt")
        let body = string(request, "body")
        guard !bundle.isEmpty, !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }
        let thread = string(request, "thre")
        return NotificationCenterRecord(
            recordID: recordID,
            bundleIdentifier: bundle,
            title: title,
            subtitle: subtitle,
            body: body,
            threadID: thread.isEmpty ? nil : thread,
            date: date(root["date"]) ?? date(request["date"]) ?? fallbackDate ?? Date()
        )
    }

    func notification(appName: String) -> NotchNotification {
        let reply = NotchNotificationPolicy.lastingReplyRoute(bundleIdentifier: bundleIdentifier, threadID: threadID)
        return NotchNotification(
            // Notification Center reuses record ids after its newest rows are
            // deleted, so the delivery time keeps ids unique across reuse.
            id: "nc-\(recordID)-\(Int(date.timeIntervalSinceReferenceDate))",
            source: .notificationCenter,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            title: title,
            subtitle: subtitle,
            body: body,
            date: date,
            threadID: threadID,
            reply: reply,
            liveBannerID: nil
        )
    }
}
