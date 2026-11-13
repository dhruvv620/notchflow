// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Only visible notification-card text is interpreted. App names in message
/// bodies do not identify a source, and unsupported/localized layouts stay unread.
enum NotificationCardPolicy {
    struct Content: Equatable {
        let app: CommunicationApp
        let sender: String
        let body: String
    }
    enum ButtonKind { case reply, send, open, dismiss }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
            .lowercased()
    }
    static func app(named label: String) -> CommunicationApp? {
        switch normalized(label) {
        case "messages", "imessage": return .messages
        case "facetime": return .faceTime
        case "phone", "iphone calls": return .phone
        case "whatsapp", "web.whatsapp.com": return .whatsapp
        case "microsoft teams", "teams": return .teams
        case "zoom", "zoom.us", "zoom workplace": return .zoom
        case "instagram", "instagram.com", "www.instagram.com": return .instagram
        default: return nil
        }
    }
    static func button(_ label: String, matches kind: ButtonKind) -> Bool {
        let value = normalized(label)
        switch kind {
        case .reply: return ["reply", "reply to message", "reply to notification"].contains(value)
        case .send: return ["send", "send reply", "send message"].contains(value)
        case .open: return ["open", "open conversation", "show", "show conversation"].contains(value)
        case .dismiss: return ["close", "dismiss", "clear notification", "close notification"].contains(value)
        }
    }
    static func content(staticTexts: [String], allowedApps: Set<CommunicationApp>) -> Content? {
        var texts: [String] = []
        for text in staticTexts {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value != texts.last { texts.append(value) }
        }
        guard let first = texts.first, let source = app(named: first), allowedApps.contains(source) else { return nil }
        texts.removeFirst()
        // The notification header can contain a relative timestamp immediately
        // after its app name. Never remove date words from the message body.
        while let first = texts.first, isHeaderTimestamp(first) { texts.removeFirst() }
        guard texts.count >= 2 else { return nil }
        let sender = texts.removeFirst()
        let body = texts.joined(separator: "\n")
        guard sender.count <= 256, !body.isEmpty else { return nil }
        return Content(app: source, sender: sender, body: String(body.prefix(8_000)))
    }
    static func isCallCard(app: CommunicationApp, texts: [String], buttonLabels: [String]) -> Bool {
        let labels = buttonLabels.map(normalized)
        let answer = labels.contains { ["answer", "accept", "accept call", "answer call"].contains($0) }
        let decline = labels.contains { ["decline", "decline call", "reject call"].contains($0) }
        guard answer && decline else { return false }
        if app == .faceTime || app == .phone { return true }
        let text = texts.joined(separator: " ").lowercased()
        return ["incoming call", "incoming video call", "incoming audio call"].contains { text.contains($0) }
    }
    static func stableID(app: CommunicationApp, nativeIdentity: String, sender: String, body: String) -> String {
        // Deterministic FNV-1a avoids Swift's process-randomized Hasher. The native
        // AX identity prevents a reply composer from moving to a replacement card.
        let value = [app.rawValue, nativeIdentity, sender, body].joined(separator: "\u{1f}")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return "notification-\(String(hash, radix: 16))"
    }
    private static func isHeaderTimestamp(_ value: String) -> Bool {
        let text = normalized(value)
        if ["now", "just now", "today", "yesterday"].contains(text) { return true }
        return text.range(of: #"^\d+\s*(s|m|h|d|sec|secs|min|mins|hr|hrs|second|seconds|minute|minutes|hour|hours|day|days)(\s+ago)?$"#, options: .regularExpression) != nil
            || text.range(of: #"^\d{1,2}:\d{2}(\s*[ap]m)?$"#, options: .regularExpression) != nil
    }
}
