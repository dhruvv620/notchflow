// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// When a meeting is near, and where to join it.
///
/// Pure logic (Foundation only), so Build.command can check it alone.
enum MeetingPolicy {
    enum Phase: Equatable, Sendable {
        /// Starts in this many seconds, within the lead time.
        case upcoming(secondsLeft: TimeInterval)
        /// Started this many seconds ago and still shown.
        case starting(secondsIn: TimeInterval)
        /// Too far away, too long underway, or over.
        case hidden
    }

    /// How early the countdown and Join appear.
    static let leadTime: TimeInterval = 5 * 60
    /// How long after the start the Join button stays.
    static let lateJoinWindow: TimeInterval = 10 * 60

    static func phase(now: Date, start: Date, end: Date) -> Phase {
        let untilStart = start.timeIntervalSince(now)
        if untilStart > leadTime || now >= end { return .hidden }
        if untilStart > 0 { return .upcoming(secondsLeft: untilStart) }
        let sinceStart = -untilStart
        return sinceStart <= lateJoinWindow ? .starting(secondsIn: sinceStart) : .hidden
    }

    /// Whether the meeting is underway (for pausing music).
    static func isInProgress(now: Date, start: Date, end: Date) -> Bool {
        now >= start && now < end
    }

    /// "4:05" before the start, "Now" once it has begun.
    static func countdownLabel(_ phase: Phase) -> String {
        switch phase {
        case .upcoming(let seconds):
            let total = Int(seconds.rounded(.up))
            return String(format: "%d:%02d", total / 60, total % 60)
        case .starting:
            return "Now"
        case .hidden:
            return ""
        }
    }

    private static let meetingHosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "around.co", "meet.jit.si", "chime.aws", "gotomeeting.com", "facetime.apple.com",
    ]

    /// The join link: the event's conference URL, else the first meeting link
    /// found in its URL, location or notes.
    static func joinURL(conferenceURL: URL?, url: URL?, location: String?, notes: String?) -> URL? {
        if let conferenceURL, isMeetingLink(conferenceURL) || conferenceURL.scheme?.hasPrefix("http") == true {
            return conferenceURL
        }
        if let url, isMeetingLink(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = firstMeetingLink(in: text) { return link }
        }
        return nil
    }

    static func isMeetingLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static let linkPattern = try? NSRegularExpression(pattern: #"https?://[^\s<>"')\]]+"#, options: [.caseInsensitive])

    static func firstMeetingLink(in text: String) -> URL? {
        guard let linkPattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in linkPattern.matches(in: text, options: [], range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let candidate = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            if let url = URL(string: candidate), isMeetingLink(url) { return url }
        }
        return nil
    }

    /// The app that hosts the call, for the label.
    static func serviceName(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return "Meeting"
    }
}
