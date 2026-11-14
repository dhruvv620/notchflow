// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Only visible notification-card text is interpreted. App names in message
/// bodies do not identify a source, and unsupported/localized layouts stay unread.
enum NotificationCardPolicy {
    struct IdentifiedText: Equatable, Sendable {
        let identifier: String
        let value: String
    }
    struct Content: Equatable {
        let app: CommunicationApp
        let sender: String
        let body: String
    }
    enum ButtonKind { case reply, send, open, dismiss }

    static func normalized(_ value: String) -> String {
        let directionMarks: Set<UInt32> = [
            0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069,
        ]
        let scalars = value.unicodeScalars.filter { !directionMarks.contains($0.value) }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    static func isNotificationContainer(subrole: String) -> Bool {
        [
            "AXNotificationCenterBanner", "AXNotificationCenterBannerStack",
            "AXNotificationCenterAlert", "AXNotificationCenterAlertStack",
        ].contains(subrole)
    }

    /// Modern Notification Center cards expose semantic `header`, `title`,
    /// `subtitle` and `body` identifiers. The source can be the header, the
    /// card's exact flattened description prefix, or a labelled source image.
    /// Message text is never searched for an app name.
    static func content(
        identifiedTexts: [IdentifiedText],
        flattenedDescription: String?,
        imageLabels: [String],
        allowedApps: Set<CommunicationApp>
    ) -> Content? {
        let acceptedIdentifiers: Set<String> = ["", "header", "title", "subtitle", "body"]
        let texts = identifiedTexts.compactMap { text -> IdentifiedText? in
            let identifier = normalizedIdentifier(text.identifier)
            let value = text.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard acceptedIdentifiers.contains(identifier), !value.isEmpty,
                  value.utf8.count <= 16_384 else { return nil }
            return IdentifiedText(identifier: identifier, value: value)
        }
        guard !texts.isEmpty else { return nil }

        func values(_ identifier: String) -> [String] {
            texts.filter { $0.identifier == identifier }.map(\.value)
        }
        let headers = values("header")
        let titles = values("title")
        let subtitles = values("subtitle")
        let bodies = values("body")

        // More than one semantic card means this root is a stack wrapper, not
        // an individual notification. Descendants are considered separately.
        guard headers.count <= 1, titles.count <= 1, subtitles.count <= 1, bodies.count <= 1 else {
            return nil
        }

        let anonymous = values("")
        let title: String
        let subtitle: String
        let bodyValue: String
        if texts.allSatisfy({ $0.identifier.isEmpty }) {
            // Older cards sometimes omit semantic identifiers. A 2–3 field
            // shape is usable only when it does not begin with an app label;
            // app-first cards belong to the stricter legacy parser below.
            guard (2...3).contains(anonymous.count), app(named: anonymous[0]) == nil else { return nil }
            title = anonymous[0]
            subtitle = anonymous.count == 3 ? anonymous[1] : ""
            bodyValue = anonymous[anonymous.count - 1]
        } else {
            guard titles.count == 1 else { return nil }
            title = titles[0]
            subtitle = subtitles.first ?? ""
            bodyValue = bodies.first ?? ""
        }

        let exactSuffix = [title, subtitle, bodyValue].filter { !$0.isEmpty }.joined(separator: ", ")
        let describedSource: CommunicationApp? = {
            guard let flattenedDescription else { return nil }
            let description = flattenedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = ", " + exactSuffix
            guard !exactSuffix.isEmpty, description.hasSuffix(suffix) else { return nil }
            return app(named: String(description.dropLast(suffix.count)))
        }()
        let headerSource = headers.first.flatMap(app(named:))
        let imageSources = Set(imageLabels.compactMap(app(named:)))
        let sourceEvidence = Set([headerSource, describedSource].compactMap { $0 }).union(imageSources)
        guard sourceEvidence.count == 1, let source = sourceEvidence.first,
              allowedApps.contains(source) else { return nil }

        // Some applications repeat their own name as the native subtitle.
        // Keep a conversation subtitle, but do not show source metadata as
        // part of the user's message.
        let visibleSubtitle = app(named: subtitle) == source ? "" : subtitle
        let body = [visibleSubtitle, bodyValue].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !body.isEmpty, title.count <= 256 else { return nil }
        return Content(app: source, sender: title, body: String(body.prefix(8_000)))
    }

    /// Parse one native card without letting the legacy text heuristic bypass
    /// semantic source conflicts. Once Notification Center supplies any of its
    /// modern field identifiers, a malformed/ambiguous semantic card must stay
    /// rejected instead of being reinterpreted as an older flat card.
    static func content(
        identifiedTexts: [IdentifiedText],
        flattenedDescription: String?,
        imageLabels: [String],
        legacyStaticTexts: [String],
        allowedApps: Set<CommunicationApp>
    ) -> Content? {
        if let semantic = content(
            identifiedTexts: identifiedTexts,
            flattenedDescription: flattenedDescription,
            imageLabels: imageLabels,
            allowedApps: allowedApps
        ) {
            return semantic
        }
        let semanticIdentifiers: Set<String> = ["header", "title", "subtitle", "body"]
        guard !identifiedTexts.contains(where: {
            semanticIdentifiers.contains(normalizedIdentifier($0.identifier))
        }) else { return nil }
        return content(staticTexts: legacyStaticTexts, allowedApps: allowedApps)
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
    private static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct NotificationBridgeDiagnostics: Equatable, Sendable {
    enum State: String, Sendable {
        case off, permissionRequired, noSources, notificationCenterUnavailable
        case waitingForBanner, unsupportedCard, captured
    }
    let state: State
    let processCount: Int
    let windowCount: Int
    let candidateCount: Int
    let recognizedCount: Int

    var message: String {
        switch state {
        case .off:
            return "Notifications are off."
        case .permissionRequired:
            return "Accessibility access is required for this exact NotchFlow copy."
        case .noSources:
            return "Select at least one notification app in Communications settings."
        case .notificationCenterUnavailable:
            return "macOS Notification Center is not currently exposing its accessibility process."
        case .waitingForBanner:
            return "Ready — waiting for a new visible notification banner from a selected app."
        case .unsupportedCard:
            return "Notification Center exposed a card, but it was not from a selected app or its layout was not recognized."
        case .captured:
            return "Captured \(recognizedCount) visible notification\(recognizedCount == 1 ? "" : "s") in the latest scan."
        }
    }

    static let off = NotificationBridgeDiagnostics(state: .off, processCount: 0, windowCount: 0,
                                                     candidateCount: 0, recognizedCount: 0)
}
