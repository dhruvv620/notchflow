// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum CommunicationApp: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case messages, faceTime, phone, whatsapp, teams, zoom, instagram
    var id: String { rawValue }
    var title: String {
        switch self {
        case .messages: return "Messages"
        case .faceTime: return "FaceTime"
        case .phone: return "iPhone calls"
        case .whatsapp: return "WhatsApp"
        case .teams: return "Teams"
        case .zoom: return "Zoom"
        case .instagram: return "Instagram"
        }
    }
    var symbol: String {
        switch self {
        case .messages, .whatsapp: return "message.fill"
        case .faceTime, .teams, .zoom: return "video.fill"
        case .phone: return "phone.fill"
        case .instagram: return "camera.fill"
        }
    }
    var bundleIdentifiers: [String] {
        switch self {
        case .messages: return ["com.apple.MobileSMS"]
        case .faceTime: return ["com.apple.FaceTime"]
        case .phone: return ["com.apple.Telephony", "com.apple.Phone", "com.apple.mobilephone"]
        case .whatsapp: return ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .zoom: return ["us.zoom.xos"]
        case .instagram: return []
        }
    }
}

struct CommunicationNotification: Identifiable, Equatable, Sendable {
    let id: String
    let app: CommunicationApp
    var sender: String
    var body: String
    var receivedAt: Date
    var canReply: Bool
    var canOpen: Bool
    var canDismiss: Bool
}

enum CommunicationNotificationAction: Sendable { case open, dismiss, beginReply, sendReply(String) }
enum CommunicationCallPhase: String, Hashable, Sendable { case incoming, connecting, active }
enum CommunicationCallAction: String, Hashable, Sendable { case answer, decline, end, mute, unmute, toggleVideo, open }

struct CommunicationCall: Identifiable, Equatable, Sendable {
    let id: String
    let app: CommunicationApp
    var caller: String
    var phase: CommunicationCallPhase
    var connectedAt: Date?
    var observedAt: Date
    var actions: Set<CommunicationCallAction>
}

enum CommunicationActionError: LocalizedError {
    case unavailable, expired, failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "This action is not exposed by the app. Open the conversation or call instead."
        case .expired: return "This item has changed or is no longer available. Refresh and try again."
        case .failed(let message): return message
        }
    }
}
