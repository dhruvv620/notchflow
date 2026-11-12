// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Defaults
import Foundation
import SwiftUI

extension Defaults.Keys {
    static let notchTabOrder = Key<[String]>("notchTabOrder", default: NotchBuiltinTab.allCases.map(\.rawValue))
    static let notchHiddenTabs = Key<[String]>("notchHiddenTabs", default: [NotchBuiltinTab.calendar.rawValue])
}

extension Notification.Name {
    static let notchTabsDidChange = Notification.Name("NotchFlow.notchTabsDidChange")
}

enum NotchBuiltinTab: String, CaseIterable, Identifiable {
    case music, shelf, timers, stats, usage, notes, clipboard, todos, calendar, terminal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .music: return "Music"
        case .shelf: return "Shelf"
        case .timers: return "Timers"
        case .stats: return "Stats"
        case .usage: return "AI Usage"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .todos: return "Todos"
        case .calendar: return "Calendar"
        case .terminal: return "Terminal"
        }
    }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .shelf: return "tray.fill"
        case .timers: return "timer"
        case .stats: return "chart.xyaxis.line"
        case .usage: return "chart.bar.doc.horizontal"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .todos: return "checklist"
        case .calendar: return "calendar"
        case .terminal: return "apple.terminal"
        }
    }
    var view: NotchViews {
        switch self {
        case .music: return .home
        case .shelf: return .shelf
        case .timers: return .timer
        case .stats: return .stats
        case .usage: return .llmUsage
        case .notes: return .notes
        case .clipboard: return .clipboard
        case .todos: return .reminders
        case .calendar: return .calendar
        case .terminal: return .terminal
        }
    }
    static func identifier(for view: NotchViews) -> String {
        allCases.first { $0.view == view }?.rawValue ?? "system-\(view)"
    }
    var featureIsEnabled: Bool {
        switch self {
        case .music: return true
        case .shelf: return Defaults[.dynamicShelf]
        case .timers: return Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab
        case .stats: return Defaults[.enableStatsFeature]
        case .usage: return Defaults[.enableLLMUsageFeature]
        case .notes: return Defaults[.enableNotes]
        case .clipboard: return Defaults[.enableClipboardManager]
        case .todos: return Defaults[.enableRemindersFeature]
        case .calendar: return Defaults[.showCalendar]
        case .terminal: return Defaults[.enableTerminalFeature]
        }
    }
    var settingsDestination: String {
        switch self {
        case .music: return "media"
        case .shelf: return "shelf"
        case .timers: return "timer"
        case .stats: return "stats"
        case .usage: return "stats"
        case .notes: return "notes"
        case .clipboard: return "clipboard"
        case .todos: return "calendar"
        case .calendar: return "calendar"
        case .terminal: return "terminal"
        }
    }
}

/// One shared order/visibility store for settings, buttons, swipe navigation and indicators.
@MainActor
final class NotchTabPreferences: ObservableObject {
    static let shared = NotchTabPreferences()
    @Published private(set) var revision = 0
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        let known = NotchBuiltinTab.allCases.map(\.rawValue)
        // Normalize built-in IDs while retaining extension choices for disconnected extensions.
        let saved = Defaults[.notchTabOrder]
        let extensionIDs = saved.filter { $0.hasPrefix("extension-") }
        let normalized = NotchTabOrderPolicy.normalizedOrder(saved, known: known + extensionIDs)
        if saved != normalized { Defaults[.notchTabOrder] = normalized }
        let hidden = Array(Set(Defaults[.notchHiddenTabs].filter { known.contains($0) || $0.hasPrefix("extension-") })).sorted()
        if Defaults[.notchHiddenTabs] != hidden { Defaults[.notchHiddenTabs] = hidden }

        Publishers.MergeMany([
            Defaults.publisher(.notchTabOrder, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.notchHiddenTabs, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.dynamicShelf, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTimerFeature, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.timerDisplayMode, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableStatsFeature, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableLLMUsageFeature, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableNotes, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableClipboardManager, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableRemindersFeature, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.showCalendar, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTerminalFeature, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableMinimalisticUI, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableThirdPartyExtensions, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableExtensionNotchExperiences, options: []).map { _ in true }.eraseToAnyPublisher(),
            Defaults.publisher(.enableExtensionNotchTabs, options: []).map { _ in true }.eraseToAnyPublisher()
        ]).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.revision += 1
            NotificationCenter.default.post(name: .notchTabsDidChange, object: nil)
        }.store(in: &subscriptions)
    }

    var orderedBuiltins: [NotchBuiltinTab] {
        NotchTabOrderPolicy.normalizedOrder(Defaults[.notchTabOrder], known: NotchBuiltinTab.allCases.map(\.rawValue))
            .compactMap(NotchBuiltinTab.init(rawValue:))
    }
    func isShown(_ id: String) -> Bool { !Defaults[.notchHiddenTabs].contains(id) }
    func setShown(_ shown: Bool, id: String) {
        var hidden = Set(Defaults[.notchHiddenTabs])
        if shown { hidden.remove(id) } else { hidden.insert(id) }
        Defaults[.notchHiddenTabs] = hidden.sorted()
    }
    private func restoredOrder(knownIDs: [String]) -> [String] {
        let extensions = (Defaults[.notchTabOrder] + knownIDs).filter { $0.hasPrefix("extension-") }
        let known = NotchBuiltinTab.allCases.map(\.rawValue) + extensions
        return NotchTabOrderPolicy.normalizedOrder(Defaults[.notchTabOrder], known: known)
    }
    func move(_ source: String, before target: String, knownIDs: [String] = []) {
        let order = restoredOrder(knownIDs: knownIDs)
        Defaults[.notchTabOrder] = NotchTabOrderPolicy.moving(source, before: target, in: order)
    }
    func move(_ source: String, over target: String, knownIDs: [String] = []) {
        let order = restoredOrder(knownIDs: knownIDs)
        Defaults[.notchTabOrder] = NotchTabOrderPolicy.moving(source, over: target, in: order)
    }
    func reset() {
        Defaults[.notchTabOrder] = NotchBuiltinTab.allCases.map(\.rawValue)
        Defaults[.notchHiddenTabs] = [NotchBuiltinTab.calendar.rawValue]
    }
}
