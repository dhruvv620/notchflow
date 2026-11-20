/*
 * NotchFlow
 * Copyright (C) 2026 dhruvv620
 * Portions Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

// MARK: - Domain models shown in the notch

struct WhatsAppChat: Identifiable, Equatable {
    /// The chat JID, e.g. `628123456789@s.whatsapp.net` or `1203630...@g.us`;
    /// for the second account, scoped (see `WhatsAppAccountSlot.scope`).
    let id: String
    var name: String
    var lastMessageTime: Date?
    var archived: Bool
    var preview: String?
    var previewIsFromMe: Bool
    var previewSender: String?
    var unreadCount: Int

    var isGroup: Bool { WhatsAppJID.isGroup(id) }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? WhatsAppJID.displayNumber(id) : trimmed
    }

    var initial: String {
        let letter = displayName.first(where: { $0.isLetter || $0.isNumber }) ?? "#"
        return String(letter).uppercased()
    }
}

struct WhatsAppMessage: Identifiable, Equatable {
    let id: String
    var chatJID: String
    let senderJID: String
    var senderName: String
    var text: String
    let timestamp: Date
    let isFromMe: Bool
    var mediaType: String? = nil
    var filename: String? = nil
    var isRevoked: Bool = false
    var isEdited: Bool = false
    /// Set when the gateway accepted a message without returning its id.
    var isPendingConfirmed: Bool = false

    static let pendingPrefix = "notchflow-pending-"

    /// A reply NotchFlow is still sending.
    var isPending: Bool { id.hasPrefix(Self.pendingPrefix) && !isPendingConfirmed }

    /// Text suitable for a one-line preview: the caption or body, or a label
    /// for the kind of media when there is no text.
    var previewText: String {
        if isRevoked { return String(localized: "This message was deleted") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return WhatsAppMessage.label(forMediaType: mediaType, filename: filename)
    }

    static func label(forMediaType mediaType: String?, filename: String?) -> String {
        switch (mediaType ?? "").lowercased() {
        case "image": return String(localized: "📷 Photo")
        case "video", "video_note", "ptv": return String(localized: "🎥 Video")
        case "audio", "ptt", "voice": return String(localized: "🎤 Voice message")
        case "document":
            if let filename, !filename.isEmpty { return "📄 \(filename)" }
            return String(localized: "📄 Document")
        case "sticker": return String(localized: "Sticker")
        case "location", "live_location": return String(localized: "📍 Location")
        case "contact", "contacts": return String(localized: "👤 Contact")
        case "call": return String(localized: "📞 Call")
        case "poll": return String(localized: "📊 Poll")
        case "": return String(localized: "Message")
        default: return String(localized: "Attachment")
        }
    }
}

/// One message to surface in the closed notch.
struct WhatsAppIncomingBanner: Equatable, Identifiable {
    let id: String
    let chatJID: String
    let chatName: String
    let senderName: String
    let text: String
    let isGroup: Bool
}

enum WhatsAppConnectionState: Equatable {
    /// The feature is turned off in settings.
    case disabled
    /// The gateway binary has not been downloaded yet.
    case notInstalled
    case installing(progress: Double?)
    case starting
    /// The gateway runs but no WhatsApp account is linked. A QR code may be showing.
    case waitingForLink
    case connected(phone: String)
    /// Linked, but the gateway lost its connection to WhatsApp for now.
    case reconnecting(phone: String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isLinked: Bool {
        switch self {
        case .connected, .reconnecting: return true
        default: return false
        }
    }
}

// MARK: - Accounts

/// The WhatsApp accounts NotchFlow can link (say, business and personal),
/// each a slot in the one gateway.
enum WhatsAppAccountSlot: String, CaseIterable, Sendable {
    case primary = "notchflow"
    case second = "notchflow-2"

    /// A chat's id in NotchFlow. The first account's chats keep their bare
    /// JIDs, so everything saved before a second account existed still
    /// matches; the second account's are "notchflow-2|<jid>", because the
    /// same person can chat with both accounts.
    func scope(_ jid: String) -> String {
        let bare = WhatsAppJID.bare(jid)
        return self == .primary ? bare : rawValue + WhatsAppJID.scopeSeparator + bare
    }

    /// The account a chat id belongs to.
    static func of(_ chatID: String) -> WhatsAppAccountSlot {
        guard let range = chatID.range(of: WhatsAppJID.scopeSeparator) else { return .primary }
        return WhatsAppAccountSlot(rawValue: String(chatID[..<range.lowerBound])) ?? .primary
    }

    /// Which account a webhook event is for: the slot it names, else the
    /// account it was received on, else the first.
    static func forEvent(sessionID: String?, deviceJID: String?, accounts: [WhatsAppAccountSlot: String]) -> WhatsAppAccountSlot {
        if let sessionID, let slot = WhatsAppAccountSlot(rawValue: sessionID) { return slot }
        if let deviceJID, let match = allCases.first(where: { WhatsAppJID.sameUser(accounts[$0] ?? "", deviceJID) }) {
            return match
        }
        return .primary
    }
}

// MARK: - JID helpers

enum WhatsAppJID {
    static let scopeSeparator = "|"

    /// The JID without the account scope: `notchflow-2|628123@s.whatsapp.net` -> `628123@s.whatsapp.net`.
    static func bare(_ id: String) -> String {
        guard let range = id.range(of: scopeSeparator) else { return id }
        return String(id[range.upperBound...])
    }

    static func isGroup(_ jid: String) -> Bool { bare(jid).hasSuffix("@g.us") }

    static func isPersonal(_ jid: String) -> Bool {
        let jid = bare(jid)
        return jid.hasSuffix("@s.whatsapp.net") || jid.hasSuffix("@lid")
    }

    /// Chats that are not conversations a person reads: status updates,
    /// newsletters (channels) and broadcast lists.
    static func isHidden(_ jid: String) -> Bool {
        let jid = bare(jid)
        return jid == "status@broadcast" || jid.hasSuffix("@newsletter") || jid.hasSuffix("@broadcast")
    }

    /// The user part of a JID without the device suffix: `628123:12@s.whatsapp.net` -> `628123`.
    static func user(_ jid: String) -> String {
        let jid = bare(jid)
        let local = jid.split(separator: "@").first.map(String.init) ?? jid
        return local.split(separator: ":").first.map(String.init) ?? local
    }

    static func displayNumber(_ jid: String) -> String {
        let user = user(jid)
        guard isPersonal(jid), bare(jid).hasSuffix("@s.whatsapp.net"), user.allSatisfy(\.isNumber) else { return user }
        return "+" + user
    }

    static func sameUser(_ lhs: String, _ rhs: String) -> Bool {
        !lhs.isEmpty && user(lhs) == user(rhs)
    }
}

// MARK: - Dates

enum WhatsAppDateParser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = plain.date(from: string) { return date }
        if let date = fractional.date(from: string) { return date }
        // Go may print more than three fractional digits, which the formatter
        // rejects. Cut the fraction down to milliseconds and try again.
        if let dot = string.firstIndex(of: ".") {
            let afterDot = string[string.index(after: dot)...]
            let digits = afterDot.prefix(while: \.isNumber)
            let rest = afterDot.dropFirst(digits.count)
            let head = String(string[..<dot])
            let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            let trimmed = head + "." + millis + String(rest)
            return fractional.date(from: trimmed)
        }
        return nil
    }

    static func format(_ date: Date) -> String {
        plain.string(from: date)
    }
}

// MARK: - Time formatting

enum WhatsAppTimeFormatter {
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    /// Compact age for the chat list: now, 6m, 22h, 3d, then a date.
    static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return String(localized: "now")
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        default: return dayFormatter.string(from: date)
        }
    }

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }
}

// MARK: - GOWA REST payloads

struct GOWAResponse<Results: Decodable>: Decodable {
    let code: String?
    let message: String?
    let results: Results?
}

struct GOWAErrorResponse: Decodable {
    let code: String?
    let message: String?
}

struct GOWALoginResults: Decodable {
    let qrLink: String?
    let qrDuration: Int?

    enum CodingKeys: String, CodingKey {
        case qrLink = "qr_link"
        case qrDuration = "qr_duration"
    }
}

struct GOWADevice: Decodable {
    let id: String
    let phoneNumber: String?
    let displayName: String?
    let state: String?
    let jid: String?

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case displayName = "display_name"
        case state
        case jid
    }
}

struct GOWAStatusResults: Decodable {
    let isConnected: Bool?
    let isLoggedIn: Bool?
    let deviceID: String?
    let jid: String?

    enum CodingKeys: String, CodingKey {
        case isConnected = "is_connected"
        case isLoggedIn = "is_logged_in"
        case deviceID = "device_id"
        case jid
    }
}

struct GOWAAppInfo: Decodable {
    let version: String?
}

struct GOWAPagination: Decodable {
    let limit: Int?
    let offset: Int?
    let total: Int?
}

struct GOWAChat: Decodable {
    let jid: String
    let name: String?
    let lastMessageTime: String?
    let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case jid
        case name
        case lastMessageTime = "last_message_time"
        case archived
    }
}

struct GOWAChatList: Decodable {
    let data: [GOWAChat]?
    let pagination: GOWAPagination?
}

struct GOWAMessage: Decodable {
    let id: String
    let chatJID: String?
    let senderJID: String?
    let senderDisplayName: String?
    let content: String?
    let timestamp: String?
    let isFromMe: Bool?
    let mediaType: String?
    let filename: String?

    enum CodingKeys: String, CodingKey {
        case id
        case chatJID = "chat_jid"
        case senderJID = "sender_jid"
        case senderDisplayName = "sender_display_name"
        case content
        case timestamp
        case isFromMe = "is_from_me"
        case mediaType = "media_type"
        case filename
    }

    func toMessage(fallbackChatJID: String) -> WhatsAppMessage {
        let chat = chatJID ?? fallbackChatJID
        let sender = senderJID ?? ""
        return WhatsAppMessage(
            id: id,
            chatJID: chat,
            senderJID: sender,
            senderName: senderDisplayName ?? WhatsAppJID.displayNumber(sender),
            text: content ?? "",
            timestamp: WhatsAppDateParser.parse(timestamp) ?? Date.distantPast,
            isFromMe: isFromMe ?? false,
            mediaType: mediaType,
            filename: filename
        )
    }
}

struct GOWAMessageList: Decodable {
    let data: [GOWAMessage]?
    let pagination: GOWAPagination?
}

struct GOWASendResults: Decodable {
    let messageID: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case status
    }
}

/// Used where the result body is irrelevant and may be a string, an object or null.
struct GOWAIgnored: Decodable {
    init(from decoder: Decoder) throws {}
}

// MARK: - Webhook events

/// A webhook delivery from the gateway, read leniently: GOWA adds fields
/// between releases, and media messages put their details under a key named
/// after the media type, so a fixed schema would drop messages it does not know.
struct WhatsAppWebhookEvent {
    let event: String
    let payload: [String: Any]
    /// The gateway slot that received it (NotchFlow's account slot).
    let sessionID: String?
    /// The account (JID) that received it.
    let deviceJID: String?

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return nil }
        self.event = event
        self.payload = object["payload"] as? [String: Any] ?? [:]
        sessionID = (object["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        deviceJID = (object["device_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func string(_ key: String) -> String? {
        guard let value = payload[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    func bool(_ key: String) -> Bool { payload[key] as? Bool ?? false }

    func strings(_ key: String) -> [String] { payload[key] as? [String] ?? [] }

    private static let mediaKeys: [(key: String, type: String)] = [
        ("image", "image"), ("video", "video"), ("video_note", "video"), ("audio", "audio"),
        ("ptt", "audio"), ("document", "document"), ("sticker", "sticker"),
        ("location", "location"), ("live_location", "location"),
        ("contact", "contact"), ("contacts_array", "contacts"), ("poll", "poll"),
    ]

    /// Builds a message from a `message` event. Returns nil for events that
    /// carry no chat, such as protocol messages.
    func message() -> WhatsAppMessage? {
        guard let id = string("id"), let chat = string("chat_id") else { return nil }
        var mediaType: String?
        var filename: String?
        for entry in Self.mediaKeys where payload[entry.key] != nil {
            mediaType = entry.type
            if let object = payload[entry.key] as? [String: Any] {
                filename = object["filename"] as? String ?? object["file_name"] as? String
            }
            break
        }
        let sender = string("from") ?? ""
        let name = string("sender_display_name") ?? string("from_name") ?? WhatsAppJID.displayNumber(sender)
        return WhatsAppMessage(
            id: id,
            chatJID: chat,
            senderJID: sender,
            senderName: name,
            text: string("body") ?? "",
            timestamp: WhatsAppDateParser.parse(string("timestamp")) ?? Date(),
            isFromMe: bool("is_from_me"),
            mediaType: mediaType,
            filename: filename
        )
    }
}
