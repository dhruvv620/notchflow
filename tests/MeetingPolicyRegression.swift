// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct MeetingPolicyRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "MeetingPolicyRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(1800)
        try require(MeetingPolicy.phase(now: start.addingTimeInterval(-600), start: start, end: end) == .hidden, "Shown 10 minutes early")
        try require(MeetingPolicy.phase(now: start.addingTimeInterval(-245), start: start, end: end) == .upcoming(secondsLeft: 245), "Not shown 4 minutes early")
        try require(MeetingPolicy.phase(now: start.addingTimeInterval(120), start: start, end: end) == .starting(secondsIn: 120), "Join gone 2 minutes in")
        try require(MeetingPolicy.phase(now: start.addingTimeInterval(900), start: start, end: end) == .hidden, "Join kept 15 minutes in")
        try require(MeetingPolicy.phase(now: end, start: start, end: end) == .hidden, "Shown after the end")
        try require(MeetingPolicy.countdownLabel(.upcoming(secondsLeft: 245)) == "4:05", "Countdown misformatted")
        try require(MeetingPolicy.countdownLabel(.upcoming(secondsLeft: 0.2)) == "0:01", "Last second shown as zero")
        try require(MeetingPolicy.countdownLabel(.starting(secondsIn: 3)) == "Now", "Start not labelled Now")
        try require(MeetingPolicy.isInProgress(now: start, start: start, end: end) && !MeetingPolicy.isInProgress(now: end, start: start, end: end), "Progress window wrong")

        let zoom = URL(string: "https://us02web.zoom.us/j/123456?pwd=x")!
        try require(MeetingPolicy.joinURL(conferenceURL: zoom, url: nil, location: nil, notes: nil) == zoom, "Conference URL ignored")
        try require(MeetingPolicy.joinURL(conferenceURL: nil, url: URL(string: "https://example.com"), location: "Room 4",
                                          notes: "Agenda\nJoin: https://meet.google.com/abc-defg-hij\nThanks") == URL(string: "https://meet.google.com/abc-defg-hij"), "Link in notes not found")
        try require(MeetingPolicy.joinURL(conferenceURL: nil, url: nil, location: "https://teams.microsoft.com/l/meetup-join/1", notes: nil)?.host == "teams.microsoft.com", "Link in location not found")
        try require(MeetingPolicy.joinURL(conferenceURL: nil, url: URL(string: "https://example.com/doc"), location: "Office", notes: "No link") == nil, "Non-meeting link accepted")
        try require(!MeetingPolicy.isMeetingLink(URL(string: "https://notzoom.us.example.com")!), "Lookalike host accepted")
        try require(MeetingPolicy.serviceName(for: zoom) == "Zoom", "Service misnamed")
        print("Meeting checks passed")
    }
}
