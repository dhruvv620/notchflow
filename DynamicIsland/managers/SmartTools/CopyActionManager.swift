// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Offer a one-tap action in the notch for copied tracking numbers, dates, addresses and sums.
    static let enableCopyActions = Key<Bool>("enableCopyActions", default: true)
}

/// One thing NotchFlow can do with what was just copied.
struct CopySuggestionAction: Identifiable, Equatable {
    enum Kind: Equatable {
        case open(URL)
        case copy(String)
        case addToCalendar(title: String, start: Date, duration: TimeInterval, allDay: Bool)
    }

    let id = UUID()
    let title: String
    let symbol: String
    let kind: Kind

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title && lhs.kind == rhs.kind }
}

struct CopySuggestion: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let actions: [CopySuggestionAction]
    var primary: CopySuggestionAction { actions[0] }
}

/// Watches the clipboard and, when the copied text is a tracking number,
/// date, address, flight, e-mail, phone number or a sum, offers the matching
/// action.
///
/// Clicking the closed notch opens it, so the closed notch only previews the
/// copy for a few seconds. The actions live in a temporary Copied tab that the
/// notch opens on while the copy is fresh; it goes away after `tabLifetime`
/// (paused while the tab is on screen) or once an action is used.
@MainActor
final class CopyActionManager: ObservableObject {
    static let shared = CopyActionManager()

    @Published private(set) var suggestion: CopySuggestion? {
        didSet {
            Self.hasLiveSuggestion = suggestion != nil
            if suggestion == nil, oldValue != nil { leaveCopiedTabIfShowing() }
        }
    }
    /// The preview under the closed notch, shown for the first few seconds.
    @Published private(set) var showsInClosedNotch = false

    /// Readable from any context (tab lists are built outside the main actor's view updates).
    nonisolated(unsafe) static var hasLiveSuggestion = false

    static let closedNotchDuration: TimeInterval = 10
    static let tabLifetime: TimeInterval = 30
    private var closedWork: DispatchWorkItem?
    private var isTabVisible = false
    private var timer: AnyCancellable?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var ownChangeCount: Int?
    private var hideWork: DispatchWorkItem?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        timer = Timer.publish(every: 0.7, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard Defaults[.enableCopyActions], pasteboard.changeCount != ownChangeCount else { return }
        // Password managers mark secrets; never look at those.
        let types = pasteboard.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            || types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return }
        guard let text = pasteboard.string(forType: .string), let candidate = CopyActionPolicy.candidate(text) else { return }
        let actions = Self.actions(for: candidate)
        guard !actions.isEmpty else { return }
        show(CopySuggestion(text: candidate, actions: Array(actions.prefix(2))))
    }

    static func actions(for text: String) -> [CopySuggestionAction] {
        var result = CopyActionPolicy.detect(text).map(action(for:))
        let types: NSTextCheckingResult.CheckingType = [.date, .address]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                if match.resultType == .date, let date = match.date,
                   !result.contains(where: { if case .addToCalendar = $0.kind { return true }; return false }) {
                    let matched = Range(match.range, in: text).map { String(text[$0]) } ?? ""
                    var title = text.replacingOccurrences(of: matched, with: "")
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                    if title.isEmpty { title = "New event" }
                    let allDay = !matched.contains(":") && Calendar.current.component(.hour, from: date) == 12
                    result.append(CopySuggestionAction(title: "Add to Calendar", symbol: "calendar.badge.plus",
                                                       kind: .addToCalendar(title: title, start: date,
                                                                            duration: match.duration > 0 ? match.duration : 3600,
                                                                            allDay: allDay)))
                } else if match.resultType == .address, let range = Range(match.range, in: text),
                          var components = URLComponents(string: "https://maps.apple.com/") {
                    components.queryItems = [URLQueryItem(name: "daddr", value: String(text[range]))]
                    if let url = components.url {
                        result.append(CopySuggestionAction(title: "Directions", symbol: "map.fill", kind: .open(url)))
                    }
                }
            }
        }
        return result
    }

    private static func action(for action: CopyAction) -> CopySuggestionAction {
        switch action {
        case .trackPackage(_, _, let url), .flight(_, let url):
            return CopySuggestionAction(title: action.title, symbol: action.symbol, kind: .open(url))
        case .call(let number):
            return CopySuggestionAction(title: action.title, symbol: action.symbol,
                                        kind: .open(URL(string: "tel:\(number)") ?? URL(fileURLWithPath: "/")))
        case .email(let address):
            return CopySuggestionAction(title: action.title, symbol: action.symbol,
                                        kind: .open(URL(string: "mailto:\(address)") ?? URL(fileURLWithPath: "/")))
        case .calculate(_, let result):
            return CopySuggestionAction(title: action.title, symbol: action.symbol, kind: .copy(result))
        }
    }

    private func show(_ suggestion: CopySuggestion) {
        withAnimation(.smooth(duration: 0.25)) {
            self.suggestion = suggestion
            showsInClosedNotch = true
        }
        scheduleClosedPreviewEnd(after: Self.closedNotchDuration)
        scheduleHide(after: Self.tabLifetime)
    }

    /// Keeps the closed-notch preview up while the pointer is over it.
    func holdOpen(_ hovering: Bool) {
        if hovering { closedWork?.cancel() } else if showsInClosedNotch { scheduleClosedPreviewEnd(after: 3) }
    }

    /// The Copied tab reports when it is on screen; its countdown pauses meanwhile.
    func copiedTabVisible(_ visible: Bool) {
        isTabVisible = visible
        if visible {
            hideWork?.cancel()
            closedWork?.cancel()
            showsInClosedNotch = false
        } else if suggestion != nil {
            scheduleHide(after: 8)
        }
    }

    private func scheduleClosedPreviewEnd(after delay: TimeInterval) {
        closedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth(duration: 0.25)) { self?.showsInClosedNotch = false }
        }
        closedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isTabVisible else { return }
            self.dismiss()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        closedWork?.cancel()
        withAnimation(.smooth(duration: 0.25)) {
            showsInClosedNotch = false
            suggestion = nil
        }
    }

    /// When the Copied tab goes away while it is the open tab, move to the first remaining tab.
    private func leaveCopiedTabIfShowing() {
        Task { @MainActor in
            guard DynamicIslandViewCoordinator.shared.currentView == .copyAction else { return }
            withAnimation(.smooth(duration: 0.25)) { TabSelectionView.validateCurrentSelection() }
        }
    }

    func perform(_ action: CopySuggestionAction) {
        switch action.kind {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .copy(let value):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            ownChangeCount = pasteboard.changeCount
        case .addToCalendar(let title, let start, let duration, let allDay):
            addToCalendar(title: title, start: start, duration: duration, allDay: allDay)
        }
        dismiss()
    }

    /// Hands Calendar an .ics file, so the user confirms the event there and
    /// NotchFlow needs no calendar write access.
    private func addToCalendar(title: String, start: Date, duration: TimeInterval, allDay: Bool) {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyyMMdd"
        let escaped = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n")
        let startLine = allDay ? "DTSTART;VALUE=DATE:\(day.string(from: start))" : "DTSTART:\(utc.string(from: start))"
        let endDate = allDay ? start.addingTimeInterval(86_400) : start.addingTimeInterval(duration)
        let endLine = allDay ? "DTEND;VALUE=DATE:\(day.string(from: endDate))" : "DTEND:\(utc.string(from: endDate))"
        let ics = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//NotchFlow//Copy to action//EN", "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)@notchflow", "DTSTAMP:\(utc.string(from: Date()))", startLine, endLine,
            "SUMMARY:\(escaped)", "END:VEVENT", "END:VCALENDAR",
        ].joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFlow-\(UUID().uuidString.prefix(8)).ics")
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            if let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.open([url], withApplicationAt: calendar, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        } catch {
            NSSound.beep()
        }
    }
}
