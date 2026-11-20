// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Countdown and Join button in the notch before meetings with a video link.
    static let enableMeetingCountdown = Key<Bool>("enableMeetingCountdown", default: true)
    /// Pause music when a meeting starts; resume it afterwards if NotchFlow paused it.
    static let pauseMusicDuringMeetings = Key<Bool>("pauseMusicDuringMeetings", default: true)
}

/// Watches the calendar for the next meeting with a video link.
@MainActor
final class MeetingManager: ObservableObject {
    static let shared = MeetingManager()

    struct Meeting: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let joinURL: URL
        var service: String { MeetingPolicy.serviceName(for: joinURL) }
    }

    @Published private(set) var meeting: Meeting?
    @Published private(set) var phase: MeetingPolicy.Phase = .hidden

    private var timer: EnergyTimer?
    private var pausedMusicForMeetingID: String?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        // Every second while a meeting is near; otherwise as the Optimizer allows.
        let timer = EnergyTimer(.meetings, soon: { [weak self] in self?.meeting != nil }) { [weak self] in
            self?.tick(now: Date())
        }
        timer.start()
        self.timer = timer
        tick(now: Date())
    }

    private func tick(now: Date) {
        guard Defaults[.enableMeetingCountdown] || Defaults[.pauseMusicDuringMeetings] else {
            if meeting != nil { meeting = nil; phase = .hidden }
            return
        }
        let next = nextMeeting(now: now)
        if next != meeting { meeting = next }
        let newPhase = next.map { MeetingPolicy.phase(now: now, start: $0.start, end: $0.end) } ?? .hidden
        if newPhase != phase { phase = newPhase }
        handleMusic(now: now)
    }

    /// The soonest timed event with a join link that has not ended.
    private func nextMeeting(now: Date) -> Meeting? {
        let calendar = CalendarManager.shared
        let candidates = (calendar.lockScreenEvents + calendar.events).filter { event in
            guard !event.isAllDay, case .event = event.type else { return false }
            return event.end > now && event.start.timeIntervalSince(now) <= MeetingPolicy.leadTime
        }
        for event in candidates.sorted(by: { $0.start < $1.start }) {
            if let url = MeetingPolicy.joinURL(conferenceURL: event.conferenceURL, url: event.url,
                                               location: event.location, notes: event.notes) {
                return Meeting(id: event.id, title: event.title, start: event.start, end: event.end, joinURL: url)
            }
        }
        return nil
    }

    private func handleMusic(now: Date) {
        let music = MusicManager.shared
        if let meeting, Defaults[.pauseMusicDuringMeetings],
           MeetingPolicy.isInProgress(now: now, start: meeting.start, end: meeting.end) {
            // Pause once, at the start; leave the user's later choices alone.
            if pausedMusicForMeetingID == nil, music.isPlaying, now.timeIntervalSince(meeting.start) < 60 {
                music.pause()
                pausedMusicForMeetingID = meeting.id
            }
        } else if let pausedID = pausedMusicForMeetingID, meeting?.id != pausedID || meeting == nil {
            // The meeting we paused for is over: pick up where it left off.
            pausedMusicForMeetingID = nil
            if !music.isPlaying { music.play() }
        }
    }

    var showsCountdown: Bool {
        guard Defaults[.enableMeetingCountdown], meeting != nil else { return false }
        if case .hidden = phase { return false }
        return true
    }

    func join() {
        guard let meeting else { return }
        NSWorkspace.shared.open(meeting.joinURL)
    }
}

/// The closed-notch meeting activity: what and when on the left, countdown
/// and Join on the right.
struct MeetingLiveActivity: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = MeetingManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    let isHovering: Bool

    static let wingWidth: CGFloat = 76

    var body: some View {
        if let meeting = manager.meeting {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                    Text(meeting.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(width: Self.wingWidth, alignment: .leading)
                .padding(.leading, 6)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))

                HStack(spacing: 5) {
                    Text(MeetingPolicy.countdownLabel(manager.phase))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isStarting ? Color.green : .white.opacity(0.85))
                    Button(action: manager.join) {
                        Text("Join")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .help("Join \(meeting.title) on \(meeting.service)")
                }
                .frame(width: Self.wingWidth, alignment: .trailing)
                .padding(.trailing, 6)
            }
            .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(meeting.title) on \(meeting.service), \(MeetingPolicy.countdownLabel(manager.phase))")
        }
    }

    private var isStarting: Bool {
        if case .starting = manager.phase { return true }
        return false
    }
}
