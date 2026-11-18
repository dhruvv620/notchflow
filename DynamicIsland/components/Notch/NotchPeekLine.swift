// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Hovering the closed notch first shows a one-line preview; clicking, or
    /// staying a moment longer when Open on hover is on, opens it fully.
    static let enableNotchPeek = Key<Bool>("enableNotchPeek", default: false)
}

/// What the peek line says: the most relevant thing right now.
struct NotchPeekSummary: Equatable {
    let symbol: String
    let text: String
    var tint: Color? = nil
}

@MainActor
enum NotchPeekSummaryBuilder {
    static func current(now: Date = Date()) -> NotchPeekSummary {
        let timer = TimerManager.shared
        if timer.isTimerActive {
            return NotchPeekSummary(symbol: "timer", text: "\(timer.timerName) · \(timer.formattedRemainingTime())", tint: timer.timerColor)
        }
        let music = MusicManager.shared
        if music.isPlaying, !music.songTitle.isEmpty {
            let artist = music.artistName.isEmpty ? "" : " – \(music.artistName)"
            return NotchPeekSummary(symbol: "music.note", text: music.songTitle + artist)
        }
        if let event = nextEvent(now: now) {
            let minutes = max(0, Int(event.start.timeIntervalSince(now) / 60))
            let when = minutes == 0 ? "now" : "in \(minutes) min"
            return NotchPeekSummary(symbol: "calendar", text: "\(event.title) \(when)")
        }
        let notifications = NotificationHub.shared.items.count
        let whatsApp = WhatsAppManager.shared.totalUnread
        if notifications > 0 || whatsApp > 0 {
            var parts: [String] = []
            if whatsApp > 0 { parts.append("\(whatsApp) WhatsApp") }
            if notifications > 0 { parts.append(notifications == 1 ? "1 notification" : "\(notifications) notifications") }
            return NotchPeekSummary(symbol: "bell.badge", text: parts.joined(separator: " · "))
        }
        let time = now.formatted(date: .omitted, time: .shortened)
        let battery = Int(BatteryStatusViewModel.shared.levelBattery.rounded())
        return NotchPeekSummary(symbol: "clock", text: battery > 0 ? "\(time) · \(battery)%" : time)
    }

    /// The next timed event starting within the hour, or happening now.
    static func nextEvent(now: Date) -> EventModel? {
        let calendar = CalendarManager.shared
        return (calendar.lockScreenEvents + calendar.events)
            .filter { event in
                guard !event.isAllDay, case .event = event.type else { return false }
                return event.end > now && event.start.timeIntervalSince(now) < 3600
            }
            .min { $0.start < $1.start }
    }
}

/// The one-line preview under the closed notch.
struct NotchPeekLine: View {
    let width: CGFloat
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    static let height: CGFloat = 26

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let summary = NotchPeekSummaryBuilder.current(now: context.date)
            HStack(spacing: 6) {
                Image(systemName: summary.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(summary.tint ?? appearance.accentColor)
                Text(summary.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: max(0, width), height: Self.height - 6)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary.text)
            .accessibilityHint("Click to open the notch")
        }
    }
}
