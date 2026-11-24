//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

/// Sidebar groups. Every settings page belongs to exactly one:
/// - core: how the notch looks and behaves as a whole
/// - notch: one page per thing that appears in the notch (tabs and live activities)
/// - tools: features you open and use
/// - system: macOS integrations outside the notch panel
/// See docs/SETTINGS.md before adding a page.
private enum SettingsTabGroup: String, CaseIterable, Identifiable {
    case core
    case notch
    case tools
    case system
    case info

    var id: String { rawValue }

    /// Display title for the section header.  `nil` means no visible header.
    var title: String? {
        switch self {
        case .core:         return String(localized: "General")
        case .notch:        return String(localized: "In the notch")
        case .tools:        return String(localized: "Work")
        case .system:       return String(localized: "System")
        case .info:         return nil
        }
    }

    /// One colour per group, for its pages' sidebar icons and headers.
    var tint: Color {
        switch self {
        case .core: return SettingsPalette.general
        case .notch: return SettingsPalette.notch
        case .tools: return SettingsPalette.work
        case .system: return SettingsPalette.system
        case .info: return SettingsPalette.system
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case tabsAndFeatures
    case communications
    case liveActivities
    case appearance
    case lockScreen
    case media
    case devices
    case timer
    case calendar
    case hudAndOSD
    case battery
    case stats
    case clipboard
    case screenAssistant
    case colorPicker
    case downloads
    case shelf
    case shortcuts
    case notes
    case smartTools
    case productivity
    case optimizer
    case glance
    case orbit
    case terminal
    case whatsapp
    case agents
    case about

    var id: String { rawValue }

    /// Which sidebar group this tab belongs to.
    var group: SettingsTabGroup {
        switch self {
        case .general, .appearance, .tabsAndFeatures, .shortcuts:                return .core
        case .media, .liveActivities, .communications, .whatsapp,
             .calendar, .timer, .shelf, .stats:                                  return .notch
        case .orbit, .agents, .productivity, .glance, .terminal, .notes, .clipboard,
             .smartTools, .screenAssistant, .colorPicker:                        return .tools
        case .hudAndOSD, .battery, .devices, .downloads, .lockScreen, .optimizer:           return .system
        case .about:                                                            return .info
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .tabsAndFeatures: return String(localized: "Tabs & Features")
        case .communications: return String(localized: "Notifications & Calls")
        case .liveActivities: return String(localized: "Live Activities")
        case .appearance: return String(localized: "Appearance")
        case .lockScreen: return String(localized: "Lock Screen")
        case .media: return String(localized: "Music")
        case .devices: return String(localized: "Devices")
        case .timer: return String(localized: "Timers")
        case .calendar: return String(localized: "Calendar & Todos")
        case .hudAndOSD: return String(localized: "Controls")
        case .battery: return String(localized: "Battery")
        case .stats: return String(localized: "Stats")
        case .clipboard: return String(localized: "Clipboard")
        case .screenAssistant: return String(localized: "Screen Assistant")
        case .colorPicker: return String(localized: "Color Picker")
        case .downloads: return String(localized: "Download Alerts")
        case .shelf: return String(localized: "Shelf")
        case .shortcuts: return String(localized: "Shortcuts")
        case .notes: return String(localized: "Notes")
        case .smartTools: return String(localized: "Smart Tools")
        case .productivity: return String(localized: "Productivity")
        case .optimizer: return String(localized: "Optimizer")
        case .glance: return String(localized: "Glance")
        case .orbit: return String(localized: "Orbit")
        case .terminal: return String(localized: "Terminal")
        case .whatsapp: return String(localized: "WhatsApp")
        case .agents: return String(localized: "AI Agents")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .tabsAndFeatures: return "rectangle.3.group"
        case .communications: return "bell.badge"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .lockScreen: return "lock.laptopcomputer"
        case .media: return "music.note"
        case .devices: return "headphones"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .stats: return "chart.xyaxis.line"
        case .clipboard: return "clipboard"
        case .screenAssistant: return "brain.head.profile"
        case .colorPicker: return "eyedropper"
        case .downloads: return "square.and.arrow.down"
        case .shelf: return "books.vertical"
        case .shortcuts: return "keyboard"
        case .notes: return "note.text"
        case .smartTools: return "wand.and.stars"
        case .productivity: return "clock.badge.checkmark"
        case .optimizer: return "gauge.with.dots.needle.33percent"
        case .glance: return "square.grid.3x2"
        case .orbit: return "circle.circle"
        case .terminal: return "apple.terminal"
        case .whatsapp: return "message.fill"
        case .agents: return "sparkles"
        case .about: return "info.circle"
        }
    }

    /// Pages take their group's colour (docs/SETTINGS_DESIGN.md).
    var tint: Color { group.tint }

    /// The one plain sentence under the page's title.
    var summary: String {
        switch self {
        case .general: return "How NotchFlow starts, opens and behaves."
        case .appearance: return "The notch's shape, colours, glass and motion."
        case .tabsAndFeatures: return "Which tabs the notch has, their order, and which features are on."
        case .shortcuts: return "Keyboard shortcuts for the notch and its tools."
        case .media: return "The music player in the notch, lyrics, and the sources it follows."
        case .communications: return "Notifications and calls in the notch, with replies."
        case .whatsapp: return "Your WhatsApp chats in the notch: read, reply and get alerts."
        case .calendar: return "Your calendar, meetings and todos in the notch."
        case .timer: return "Timers and Pomodoro in the notch."
        case .shelf: return "A place in the notch to drop files and keep them handy."
        case .liveActivities: return "What shows under the closed notch: recording, Focus, camera and more."
        case .stats: return "Your Mac's CPU, memory, network and more in the notch."
        case .orbit: return "Projects, people and loose ends that keep track of themselves. Everything stays on this Mac."
        case .agents: return "Start, watch and approve Claude Code, Codex, Gemini and Cursor from the notch."
        case .productivity: return "Time tracking, workspaces, promises and the window stash."
        case .glance: return "A board of panels over your screen, one key away."
        case .terminal: return "A terminal in the notch, with tabs."
        case .notes: return "Quick notes in the notch."
        case .clipboard: return "Everything you copied, in the notch."
        case .smartTools: return "Copy-to-action, smart replies, build watching and focus guard."
        case .screenAssistant: return "Ask AI about what's on your screen."
        case .colorPicker: return "Pick any colour on screen and copy it."
        case .hudAndOSD: return "Volume, brightness and keyboard controls, shown in the notch."
        case .battery: return "Charging and battery alerts."
        case .devices: return "Headphones and other Bluetooth devices."
        case .downloads: return "See downloads finish in the notch."
        case .lockScreen: return "Widgets on the lock screen: music, timers, weather and more."
        case .optimizer: return "Keep NotchFlow light on CPU, memory and battery."
        case .about: return "Version, updates and credits."
        }
    }

    /// The feature's main switch, shown in its page's header.
    var masterKey: Defaults.Key<Bool>? {
        switch self {
        case .orbit: return .enableOrbit
        case .agents: return .enableAgentsFeature
        case .timer: return .enableTimerFeature
        case .stats: return .enableStatsFeature
        case .notes: return .enableNotes
        case .clipboard: return .enableClipboardManager
        case .terminal: return .enableTerminalFeature
        case .whatsapp: return .enableWhatsAppFeature
        case .glance: return .enableGlance
        case .shelf: return .dynamicShelf
        case .colorPicker: return .enableColorPickerFeature
        case .screenAssistant: return .enableScreenAssistant
        case .downloads: return .enableDownloadListener
        case .shortcuts: return .enableShortcuts
        default: return nil
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct SettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?

    var id: String { "\(tab.rawValue)-\(title)" }
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        fileprivate let tab: SettingsTab
    }

    @Published fileprivate var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    fileprivate func focus(on entry: SettingsSearchEntry) {
        guard let highlightID = entry.highlightID else { return }
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: entry.tab)
        activateHighlight(id: highlightID)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        pageContent
            // The form shows the page's background, so header and rows sit on one colour.
            .scrollContentBackground(.hidden)
            // The same header on every page (docs/SETTINGS_DESIGN.md), placed by the
            // system below the toolbar; the page scrolls under it.
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsTabHeader(tab: tab)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageContent: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    highlightCoordinator.consumeScrollRequest(request)
                }
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText: String = ""
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    // For the sidebar's "needs you" dots.
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @ObservedObject private var agentHub = AgentHub.shared

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                SettingsSidebarSearchBar(
                    text: $searchText,
                    suggestions: searchSuggestions,
                    onSuggestionSelected: handleSearchSuggestionSelection
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                List(selection: selectionBinding) {
                    ForEach(groupedFilteredTabs, id: \.group) { section in
                        Section {
                            ForEach(section.tabs) { tab in
                                NavigationLink(value: tab) {
                                    sidebarRow(for: tab)
                                }
                            }
                        } header: {
                            if let title = section.group.title {
                                Text(title)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
                .environment(\.defaultMinListRowHeight, 44)

                VStack(spacing: 0) {
                    Divider()
                    SettingsAppControls()
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } detail: {
            detailView(for: resolvedSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        // No toolbar band: a clear title bar with just the window buttons, like
        // System Settings, and every page starts right below it.
        .toolbar(.hidden, for: .windowToolbar)
        .environmentObject(highlightCoordinator)
        .formStyle(.grouped)
        // One accent and one background for every page.
        .tint(SettingsPalette.accent)
        .frame(minWidth: 760, idealWidth: 860, maxWidth: .infinity, minHeight: 560, idealHeight: 680, maxHeight: .infinity)
        .onChange(of: searchText) { _, newValue in
            let matches = tabsMatchingSearch(newValue)
            guard let firstMatch = matches.first else { return }
            if !matches.contains(resolvedSelection) {
                selectedTab = firstMatch
            }
        }
    }

    private var resolvedSelection: SettingsTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .general)
    }

    private var filteredTabs: [SettingsTab] {
        tabsMatchingSearch(searchText)
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection },
            set: { newValue in
                selectedTab = newValue
            }
        )
    }

    @ViewBuilder
    private func sidebarIcon(for tab: SettingsTab) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tab.tint.gradient)
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
    }

    /// Pages that need you get an orange dot in the sidebar.
    private func needsAttention(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .whatsapp:
            guard Defaults[.enableWhatsAppFeature] else { return false }
            switch whatsApp.state {
            case .failed, .waitingForLink: return true
            default: return false
            }
        case .agents:
            return Defaults[.enableAgentsFeature] && agentHub.bridgeError != nil
        case .orbit:
            return Defaults[.enableOrbit] && (OrbitLinear.shared.lastError != nil
                || (Orbit.shared.vaultStatus?.hasPrefix("Couldn't") ?? false))
        default:
            return false
        }
    }

    @ViewBuilder
    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(for: tab)
            Text(LocalizedStringKey(tab.title))
            if needsAttention(tab) {
                Spacer(minLength: 4)
                Circle().fill(SettingsPalette.warn).frame(width: 7, height: 7)
                    .accessibilityLabel("Needs attention")
            }
            if tab == .downloads {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(SettingsPalette.accent)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var availableTabs: [SettingsTab] {
        // Ordered to match the sidebar groups (see SettingsTabGroup).
        let ordered: [SettingsTab] = [
            // General
            .general,
            .appearance,
            .tabsAndFeatures,
            .shortcuts,
            // In the notch
            .media,
            .communications,
            .whatsapp,
            .calendar,
            .timer,
            .shelf,
            .liveActivities,
            .stats,
            // Work
            .orbit,
            .agents,
            .productivity,
            .glance,
            .terminal,
            .notes,
            .clipboard,
            .smartTools,
            .screenAssistant,
            .colorPicker,
            // System
            .hudAndOSD,
            .battery,
            .devices,
            .downloads,
            .lockScreen,
            .optimizer,
            // Info
            .about
        ]

        return ordered.filter { isTabVisible($0) }
    }

    /// Groups the filtered tabs into sidebar sections, preserving both
    /// the group order and the per-group tab order from `availableTabs`.
    private var groupedFilteredTabs: [(group: SettingsTabGroup, tabs: [SettingsTab])] {
        let visible = filteredTabs
        var result: [(group: SettingsTabGroup, tabs: [SettingsTab])] = []

        for group in SettingsTabGroup.allCases {
            let tabs = visible.filter { $0.group == group }
            if !tabs.isEmpty {
                result.append((group: group, tabs: tabs))
            }
        }

        return result
    }

    private func tabsMatchingSearch(_ query: String) -> [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableTabs }

        let entryMatches = searchEntries(matching: trimmed)
        let matchingTabs = Set(entryMatches.map(\.tab))

        return availableTabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(trimmed) || matchingTabs.contains(tab)
        }
    }

    private var searchSuggestions: [SettingsSearchEntry] {
        Array(searchEntries(matching: searchText).filter { $0.tab != .downloads }.prefix(8))
    }

    private func handleSearchSuggestionSelection(_ suggestion: SettingsSearchEntry) {
        guard suggestion.tab != .downloads else { return }
        highlightCoordinator.focus(on: suggestion)
        selectedTab = suggestion.tab
    }

    private struct SettingsSidebarSearchBar: View {
        @Binding var text: String
        let suggestions: [SettingsSearchEntry]
        let onSuggestionSelected: (SettingsSearchEntry) -> Void

        @FocusState private var isFocused: Bool
        @State private var hoveredSuggestionID: SettingsSearchEntry.ID?

        var body: some View {
            VStack(spacing: 6) {
                searchField
                if showSuggestions {
                    suggestionList
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSuggestions)
        }

        private var showSuggestions: Bool {
            isFocused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
        }

        private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)

                TextField("Search Settings", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(triggerFirstSuggestion)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }

        private var suggestionList: some View {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(suggestion.tab.tint)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: suggestion.tab.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(suggestion.title))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(LocalizedStringKey(suggestion.tab.title))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: suggestion))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSuggestionID = hovering ? suggestion.id : (hoveredSuggestionID == suggestion.id ? nil : hoveredSuggestionID)
                    }

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        private func rowBackground(for suggestion: SettingsSearchEntry) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredSuggestionID == suggestion.id ? Color.white.opacity(0.08) : Color.clear)
        }

        private func selectSuggestion(_ suggestion: SettingsSearchEntry) {
            onSuggestionSelected(suggestion)
            isFocused = false
        }

        private func triggerFirstSuggestion() {
            guard let first = suggestions.first else { return }
            selectSuggestion(first)
        }
    }

    private func searchEntries(matching query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return settingsSearchIndex
            .filter { availableTabs.contains($0.tab) }
            .filter { entry in
                entry.title.localizedCaseInsensitiveContains(trimmed) ||
                entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
    }

    private var settingsSearchIndex: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(tab: .communications, title: "Enable Communications", keywords: ["notifications", "messages", "imessage", "whatsapp", "instagram", "accessibility", "permission"], highlightID: SettingsTab.communications.highlightID(for: "Enable Communications")),
            SettingsSearchEntry(tab: .communications, title: "Notification apps", keywords: ["reply", "inbox", "message", "notification", "preview", "focus"], highlightID: SettingsTab.communications.highlightID(for: "Notification apps")),
            SettingsSearchEntry(tab: .communications, title: "Call Island", keywords: ["call", "facetime", "phone", "teams", "zoom", "answer", "decline", "mute"], highlightID: SettingsTab.communications.highlightID(for: "Call Island")),
            SettingsSearchEntry(tab: .tabsAndFeatures, title: "Tabs & Features", keywords: ["tabs", "features", "notch", "applications", "options"], highlightID: SettingsTab.tabsAndFeatures.highlightID(for: "Tabs & Features")),
            SettingsSearchEntry(tab: .tabsAndFeatures, title: "Tab visibility and order", keywords: ["reorder", "drag", "drop", "hide", "show", "music", "timers", "todos", "calendar"], highlightID: SettingsTab.tabsAndFeatures.highlightID(for: "Tab visibility and order")),
            SettingsSearchEntry(tab: .tabsAndFeatures, title: "Notch feature controls", keywords: ["enable", "disable", "clipboard", "stats", "notes", "terminal"], highlightID: SettingsTab.tabsAndFeatures.highlightID(for: "Notch feature controls")),
            // General
            SettingsSearchEntry(tab: .general, title: "Enable Minimalistic UI", keywords: ["minimalistic", "ui mode", "general"], highlightID: SettingsTab.general.highlightID(for: "Enable Minimalistic UI")),
            SettingsSearchEntry(tab: .general, title: "Menubar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon")),
            SettingsSearchEntry(tab: .general, title: "Opens on", keywords: ["tab", "home tab", "default tab", "last tab", "remember", "smart tab", "open on", "whatsapp", "music", "start"], highlightID: SettingsTab.general.highlightID(for: "Opens on")),
            SettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
            SettingsSearchEntry(tab: .general, title: "Show on all displays", keywords: ["multi-display", "external monitor"], highlightID: SettingsTab.general.highlightID(for: "Show on all displays")),
            SettingsSearchEntry(tab: .general, title: "Show on a specific display", keywords: ["preferred screen", "display picker"], highlightID: SettingsTab.general.highlightID(for: "Show on a specific display")),
            SettingsSearchEntry(tab: .general, title: "Automatically switch displays", keywords: ["auto switch", "displays"], highlightID: SettingsTab.general.highlightID(for: "Automatically switch displays")),
            SettingsSearchEntry(tab: .general, title: "Hide Dynamic Island during screenshots & recordings", keywords: ["privacy", "screenshot", "recording"], highlightID: SettingsTab.general.highlightID(for: "Hide Dynamic Island during screenshots & recordings")),
            SettingsSearchEntry(tab: .general, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.general.highlightID(for: "Enable gestures")),
            SettingsSearchEntry(tab: .general, title: "Close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.general.highlightID(for: "Close gesture")),
            SettingsSearchEntry(tab: .general, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.general.highlightID(for: "Reverse swipe gestures")),
            SettingsSearchEntry(tab: .general, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.general.highlightID(for: "Reverse scroll gestures")),
            SettingsSearchEntry(tab: .general, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.general.highlightID(for: "Extend hover area")),
            SettingsSearchEntry(tab: .general, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.general.highlightID(for: "Enable haptics")),
            SettingsSearchEntry(tab: .general, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.general.highlightID(for: "Open notch on hover")),
            SettingsSearchEntry(tab: .general, title: "Peek before opening", keywords: ["peek", "preview", "hover", "accidental"], highlightID: SettingsTab.general.highlightID(for: "Peek before opening")),
            SettingsSearchEntry(tab: .general, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.general.highlightID(for: "External display style")),
            SettingsSearchEntry(tab: .general, title: "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.general.highlightID(for: "Hide until hovered")),
            SettingsSearchEntry(tab: .general, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.general.highlightID(for: "Notch display height")),

            // Live Activities
            SettingsSearchEntry(tab: .liveActivities, title: "Notice screen recording", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Notice screen recording")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show a recording dot", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show a recording dot")),
            SettingsSearchEntry(tab: .liveActivities, title: "Notice Focus", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Notice Focus")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show the Focus icon", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show the Focus icon")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show the Focus name", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show the Focus name")),
            SettingsSearchEntry(tab: .liveActivities, title: "Camera in use", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Camera in use")),
            SettingsSearchEntry(tab: .liveActivities, title: "Microphone in use", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Microphone in use")),
            SettingsSearchEntry(tab: .media, title: "Show music in the closed notch", keywords: ["music", "now playing"], highlightID: SettingsTab.media.highlightID(for: "Show music in the closed notch")),

            // Battery (Charge)
            SettingsSearchEntry(tab: .battery, title: "Show battery indicator", keywords: ["battery hud", "charge"], highlightID: SettingsTab.battery.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .battery, title: "Show battery percentage", keywords: ["battery percent"], highlightID: SettingsTab.battery.highlightID(for: "Show battery percentage")),
            SettingsSearchEntry(tab: .battery, title: "Show power status notifications", keywords: ["notifications", "power"], highlightID: SettingsTab.battery.highlightID(for: "Show power status notifications")),
            SettingsSearchEntry(tab: .battery, title: "Show power status icons", keywords: ["power icons", "charging icon"], highlightID: SettingsTab.battery.highlightID(for: "Show power status icons")),
            SettingsSearchEntry(tab: .battery, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.battery.highlightID(for: "Play low battery alert sound")),
            SettingsSearchEntry(tab: .battery, title: "Charging HUD", keywords: ["battery", "charging", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Charging HUD")),
            SettingsSearchEntry(tab: .battery, title: "Low battery HUD", keywords: ["battery", "low", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Low battery HUD")),
            SettingsSearchEntry(tab: .battery, title: "Fully charged HUD", keywords: ["battery", "full", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Fully charged HUD")),
            SettingsSearchEntry(tab: .battery, title: "Charging duration", keywords: ["charging", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Charging duration")),
            SettingsSearchEntry(tab: .battery, title: "Low battery duration", keywords: ["low battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Low battery duration")),
            SettingsSearchEntry(tab: .battery, title: "Full battery duration", keywords: ["full battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Full battery duration")),
            SettingsSearchEntry(tab: .battery, title: "Test charging HUD", keywords: ["battery", "test", "charging", "preview"], highlightID: nil),
            SettingsSearchEntry(tab: .battery, title: "Test low battery HUD", keywords: ["battery", "test", "low", "preview"], highlightID: nil),
            SettingsSearchEntry(tab: .battery, title: "Test full battery HUD", keywords: ["battery", "test", "full", "preview"], highlightID: nil),
            SettingsSearchEntry(tab: .battery, title: "Low battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Low battery style")),
            SettingsSearchEntry(tab: .battery, title: "Low battery threshold", keywords: ["battery", "threshold", "percent"], highlightID: SettingsTab.battery.highlightID(for: "Low battery threshold")),
            SettingsSearchEntry(tab: .battery, title: "Full battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Full battery style")),
            SettingsSearchEntry(tab: .battery, title: "Full charge threshold", keywords: ["battery", "threshold", "full"], highlightID: SettingsTab.battery.highlightID(for: "Full charge threshold")),

            // HUDs
            SettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
            SettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
            SettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
            SettingsSearchEntry(tab: .devices, title: "Color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Color-coded battery display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Color-coded volume display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Smooth color transitions")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

            // Custom OSD
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Keyboard Backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Keyboard Backlight OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume step", keywords: ["volume", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume fine step", keywords: ["volume", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume fine step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness step", keywords: ["brightness", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness fine step", keywords: ["brightness", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness fine step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC app integration", keywords: ["ddc", "third party", "external", "display", "betterdisplay", "lunar"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC app integration")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC provider", keywords: ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC provider")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

            // Media
            SettingsSearchEntry(tab: .media, title: "Music source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music source")),
            SettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
            SettingsSearchEntry(tab: .media, title: "Sneak peek style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak peek style")),
            SettingsSearchEntry(tab: .media, title: "Lyrics", keywords: ["lyrics", "song text"], highlightID: SettingsTab.media.highlightID(for: "Lyrics")),
            SettingsSearchEntry(tab: .media, title: "Moving artwork", keywords: ["canvas", "live canvas", "album art", "dynamic island", "spotify canvas"], highlightID: SettingsTab.media.highlightID(for: "Moving artwork")),
            SettingsSearchEntry(tab: .media, title: "Hide it when nothing plays", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Hide it when nothing plays")),
            SettingsSearchEntry(tab: .media, title: "Output button", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Output button")),
            SettingsSearchEntry(tab: .media, title: "Artwork tilt on the lock screen", keywords: ["parallax", "lock screen", "album art"], highlightID: SettingsTab.media.highlightID(for: "Artwork tilt on the lock screen")),
            SettingsSearchEntry(tab: .media, title: "Artwork tilt", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Artwork tilt")),

            // Calendar
            SettingsSearchEntry(tab: .calendar, title: "Enable Todos tab", keywords: ["reminders", "apple reminders", "tasks", "lists", "hide todos"], highlightID: SettingsTab.calendar.highlightID(for: "Show Reminders tab")),
            SettingsSearchEntry(tab: .calendar, title: "Show calendar", keywords: ["calendar", "events"], highlightID: SettingsTab.calendar.highlightID(for: "Show calendar")),
            SettingsSearchEntry(tab: .calendar, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.calendar.highlightID(for: "Enable reminder live activity")),
            SettingsSearchEntry(tab: .calendar, title: "Countdown style", keywords: ["reminder countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Countdown style")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show next calendar event", keywords: ["calendar widget", "lock screen", "next event"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show next calendar event")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show events within the next", keywords: ["calendar widget", "lookahead"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show events within the next")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show events from all calendars", keywords: ["calendar widget", "selection"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show events from all calendars")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show countdown", keywords: ["calendar widget", "countdown"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show countdown")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show event for entire duration", keywords: ["calendar widget", "duration"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show event for entire duration")),
            SettingsSearchEntry(tab: .lockScreen, title: "Hide active event and show next upcoming event", keywords: ["calendar widget", "after start"], highlightID: SettingsTab.lockScreen.highlightID(for: "Hide active event and show next upcoming event")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show time remaining", keywords: ["calendar widget", "remaining"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show time remaining")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show start time after event begins", keywords: ["calendar widget", "start time"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show start time after event begins")),
            SettingsSearchEntry(tab: .calendar, title: "Hide all-day events", keywords: ["calendar", "all-day"], highlightID: SettingsTab.calendar.highlightID(for: "Hide all-day events")),
            SettingsSearchEntry(tab: .calendar, title: "Hide completed reminders", keywords: ["reminder", "completed"], highlightID: SettingsTab.calendar.highlightID(for: "Hide completed reminders")),
            SettingsSearchEntry(tab: .calendar, title: "Show full event titles", keywords: ["calendar", "titles"], highlightID: SettingsTab.calendar.highlightID(for: "Show full event titles")),
            SettingsSearchEntry(tab: .calendar, title: "Auto-scroll to next event", keywords: ["calendar", "scroll"], highlightID: SettingsTab.calendar.highlightID(for: "Auto-scroll to next event")),

            // Shelf
            SettingsSearchEntry(tab: .shelf, title: "Use Shelf", keywords: ["shelf", "dock"], highlightID: SettingsTab.shelf.highlightID(for: "Use Shelf")),
            SettingsSearchEntry(tab: .shelf, title: "Open shelf tab by default if items added", keywords: ["auto open", "shelf tab"], highlightID: SettingsTab.shelf.highlightID(for: "Open shelf tab by default if items added")),
            SettingsSearchEntry(tab: .shelf, title: "Copy items on drag", keywords: ["shelf", "drag", "copy"], highlightID: SettingsTab.shelf.highlightID(for: "Copy items on drag")),
            SettingsSearchEntry(tab: .shelf, title: "Remove from shelf after dragging", keywords: ["shelf", "drag", "remove"], highlightID: SettingsTab.shelf.highlightID(for: "Remove from shelf after dragging")),
            SettingsSearchEntry(tab: .shelf, title: "Quick Share Service", keywords: ["shelf", "share", "airdrop", "localsend"], highlightID: SettingsTab.shelf.highlightID(for: "Quick Share Service")),
            SettingsSearchEntry(tab: .shelf, title: "LocalSend Device Picker Style", keywords: ["localsend", "glass", "picker", "material"], highlightID: SettingsTab.shelf.highlightID(for: "Device Picker Style")),

            // Appearance
            SettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
            SettingsSearchEntry(tab: .appearance, title: "Settings icon in notch", keywords: ["settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Settings icon in notch")),
            SettingsSearchEntry(tab: .appearance, title: "Element style", keywords: ["subtle", "graphite", "gradient", "cards"], highlightID: SettingsTab.appearance.highlightID(for: "Element style")),
            SettingsSearchEntry(tab: .appearance, title: "Island size", keywords: ["compact", "spacious", "custom", "height", "width"], highlightID: SettingsTab.appearance.highlightID(for: "Island size")),
            SettingsSearchEntry(tab: .appearance, title: "Custom island size", keywords: ["width", "height", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Custom island size")),
            SettingsSearchEntry(tab: .appearance, title: "Corner radius", keywords: ["radius", "rounded", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Corner radius")),
            SettingsSearchEntry(tab: .appearance, title: "Island background", keywords: ["black", "dynamic", "glass", "liquid", "frosted", "material"], highlightID: SettingsTab.appearance.highlightID(for: "Island background")),
            SettingsSearchEntry(tab: .appearance, title: "Island outline", keywords: ["border", "stroke", "outline"], highlightID: SettingsTab.appearance.highlightID(for: "Island outline")),
            SettingsSearchEntry(tab: .appearance, title: "Notch accent color", keywords: ["adaptive", "artwork", "fixed", "system", "accent", "slider", "playback", "visualizer"], highlightID: SettingsTab.appearance.highlightID(for: "Notch accent color")),
            SettingsSearchEntry(tab: .appearance, title: "Artwork glow", keywords: ["artwork", "glow", "shadow"], highlightID: SettingsTab.appearance.highlightID(for: "Artwork glow")),
            SettingsSearchEntry(tab: .appearance, title: "Reduce notch motion", keywords: ["animation", "accessibility", "motion"], highlightID: SettingsTab.appearance.highlightID(for: "Reduce notch motion")),
            SettingsSearchEntry(tab: .appearance, title: "Activity indicators", keywords: ["dots", "icons", "carousel", "indicator"], highlightID: SettingsTab.appearance.highlightID(for: "Activity indicators")),
            SettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
            SettingsSearchEntry(tab: .appearance, title: "Round the top corners when open", keywords: ["corner radius scaling", "corners", "rounded"], highlightID: SettingsTab.appearance.highlightID(for: "Round the top corners when open")),
            SettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
            SettingsSearchEntry(tab: .appearance, title: "Closed notch / pill width", keywords: ["closed notch", "pill", "width"], highlightID: SettingsTab.appearance.highlightID(for: "Closed notch / pill width")),
            SettingsSearchEntry(tab: .media, title: "Colour it with the artwork", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.media.highlightID(for: "Colour it with the artwork")),
            SettingsSearchEntry(tab: .appearance, title: "Enable Dynamic mirror", keywords: ["mirror", "reflection"], highlightID: SettingsTab.appearance.highlightID(for: "Enable Dynamic mirror")),
            SettingsSearchEntry(tab: .appearance, title: "Mirror shape", keywords: ["mirror shape", "circle", "rectangle"], highlightID: SettingsTab.appearance.highlightID(for: "Mirror shape")),
            SettingsSearchEntry(tab: .appearance, title: "Idle Animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Idle Animation")),
            SettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),

            // Lock Screen
            SettingsSearchEntry(tab: .lockScreen, title: "Preview lock screen widgets", keywords: ["preview", "lock screen", "widgets"], highlightID: SettingsTab.lockScreen.highlightID(for: "Preview lock screen widgets")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable lock screen live activity", keywords: ["lock screen", "live activity"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable lock screen live activity")),
            SettingsSearchEntry(tab: .lockScreen, title: "Play lock/unlock sounds", keywords: ["chime", "sound"], highlightID: SettingsTab.lockScreen.highlightID(for: "Play lock/unlock sounds")),
            SettingsSearchEntry(tab: .lockScreen, title: "Material", keywords: ["glass", "frosted", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen media panel", keywords: ["media panel", "lock screen media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen media panel")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show media app icon", keywords: ["app icon", "media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show media app icon")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show panel border", keywords: ["panel border"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show panel border")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable media panel blur", keywords: ["blur", "media panel"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable media panel blur")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen timer", keywords: ["timer widget", "lock screen timer"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen timer")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen weather", keywords: ["weather widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen weather")),
            SettingsSearchEntry(tab: .lockScreen, title: "Layout", keywords: ["inline", "circular", "weather layout"], highlightID: SettingsTab.lockScreen.highlightID(for: "Layout")),
            SettingsSearchEntry(tab: .lockScreen, title: "Weather data provider", keywords: ["wttr", "open meteo"], highlightID: SettingsTab.lockScreen.highlightID(for: "Weather data provider")),
            SettingsSearchEntry(tab: .lockScreen, title: "Temperature unit", keywords: ["celsius", "fahrenheit"], highlightID: SettingsTab.lockScreen.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show location label", keywords: ["location", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show location label")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging status", keywords: ["charging", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging status")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging percentage", keywords: ["charging percentage"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging percentage")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show battery indicator", keywords: ["battery gauge", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use MacBook icon when on battery", keywords: ["laptop icon", "battery"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use MacBook icon when on battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show Bluetooth battery", keywords: ["bluetooth", "gauge"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show Bluetooth battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show AQI widget", keywords: ["air quality", "aqi"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show AQI widget")),
            SettingsSearchEntry(tab: .lockScreen, title: "Air quality scale", keywords: ["aqi", "scale"], highlightID: SettingsTab.lockScreen.highlightID(for: "Air quality scale")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use colored gauges", keywords: ["gauge tint", "monochrome"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use colored gauges")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen reminder", keywords: ["lock screen", "reminder widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen reminder")),
            SettingsSearchEntry(tab: .lockScreen, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.lockScreen.highlightID(for: "Chip color")),
            SettingsSearchEntry(tab: .lockScreen, title: "Reminder alignment", keywords: ["reminder", "alignment", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder alignment")),
            SettingsSearchEntry(tab: .lockScreen, title: "Reminder vertical offset", keywords: ["reminder", "offset", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder vertical offset")),


            // Shortcuts
            SettingsSearchEntry(tab: .shortcuts, title: "Use Shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Use Shortcuts")),

            // Timer
            SettingsSearchEntry(tab: .timer, title: "Don't disturb me during focus", keywords: ["pomodoro", "focus", "do not disturb", "notifications", "quiet", "distraction"], highlightID: SettingsTab.timer.highlightID(for: "Don't disturb me during focus")),
            SettingsSearchEntry(tab: .timer, title: "Let calls through", keywords: ["pomodoro", "focus", "calls"], highlightID: SettingsTab.timer.highlightID(for: "Let calls through")),
            SettingsSearchEntry(tab: .timer, title: "Also silence macOS (Focus)", keywords: ["pomodoro", "focus", "shortcuts", "do not disturb"], highlightID: SettingsTab.timer.highlightID(for: "Also silence macOS (Focus)")),
            SettingsSearchEntry(tab: .timer, title: "Use Timers", keywords: ["timer", "enable"], highlightID: SettingsTab.timer.highlightID(for: "Use Timers")),
            SettingsSearchEntry(tab: .timer, title: "Mirror macOS Clock timers", keywords: ["system timer", "clock app"], highlightID: SettingsTab.timer.highlightID(for: "Mirror macOS Clock timers")),
            SettingsSearchEntry(tab: .timer, title: "Timer tint", keywords: ["timer colour", "preset"], highlightID: SettingsTab.timer.highlightID(for: "Timer tint")),
            SettingsSearchEntry(tab: .timer, title: "Solid colour", keywords: ["timer colour", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Solid colour")),
            SettingsSearchEntry(tab: .timer, title: "Progress style", keywords: ["progress", "bar", "ring"], highlightID: SettingsTab.timer.highlightID(for: "Progress style")),
            SettingsSearchEntry(tab: .timer, title: "Accent colour", keywords: ["accent", "timer"], highlightID: SettingsTab.timer.highlightID(for: "Accent colour")),

            // Stats
            SettingsSearchEntry(tab: .stats, title: "Use Stats", keywords: ["stats", "monitoring"], highlightID: SettingsTab.stats.highlightID(for: "Use Stats")),
            SettingsSearchEntry(tab: .stats, title: "AI usage tab", keywords: ["llm", "usage", "ai", "monitor"], highlightID: SettingsTab.stats.highlightID(for: "AI usage tab")),
            SettingsSearchEntry(tab: .stats, title: "Claude Provider", keywords: ["llm", "claude", "provider", "toggle"], highlightID: SettingsTab.stats.highlightID(for: "Claude Provider")),
            SettingsSearchEntry(tab: .stats, title: "Codex Provider", keywords: ["llm", "codex", "provider", "toggle"], highlightID: SettingsTab.stats.highlightID(for: "Codex Provider")),
            SettingsSearchEntry(tab: .stats, title: "Cursor Provider", keywords: ["llm", "cursor", "provider", "toggle"], highlightID: SettingsTab.stats.highlightID(for: "Cursor Provider")),
            SettingsSearchEntry(tab: .stats, title: "Stop when the notch closes", keywords: ["stats", "auto stop"], highlightID: SettingsTab.stats.highlightID(for: "Stop when the notch closes")),
            SettingsSearchEntry(tab: .stats, title: "CPU", keywords: ["cpu", "graph"], highlightID: SettingsTab.stats.highlightID(for: "CPU")),
            SettingsSearchEntry(tab: .stats, title: "Temperature unit", keywords: ["cpu", "temperature", "celsius", "fahrenheit"], highlightID: SettingsTab.stats.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .stats, title: "Memory", keywords: ["memory", "ram"], highlightID: SettingsTab.stats.highlightID(for: "Memory")),
            SettingsSearchEntry(tab: .stats, title: "GPU", keywords: ["gpu", "graphics"], highlightID: SettingsTab.stats.highlightID(for: "GPU")),
            SettingsSearchEntry(tab: .stats, title: "Network", keywords: ["network", "graph"], highlightID: SettingsTab.stats.highlightID(for: "Network")),
            SettingsSearchEntry(tab: .stats, title: "Disk", keywords: ["disk", "io"], highlightID: SettingsTab.stats.highlightID(for: "Disk")),

            // Clipboard
            SettingsSearchEntry(tab: .clipboard, title: "Use Clipboard", keywords: ["clipboard", "manager"], highlightID: SettingsTab.clipboard.highlightID(for: "Use Clipboard")),
            SettingsSearchEntry(tab: .clipboard, title: "Show it as", keywords: ["list", "grid", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Show it as")),
            SettingsSearchEntry(tab: .clipboard, title: "History Size", keywords: ["history", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "History Size")),

            // Screen Assistant
            SettingsSearchEntry(tab: .screenAssistant, title: "Use Screen Assistant", keywords: ["screen assistant", "ai"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Use Screen Assistant")),
            SettingsSearchEntry(tab: .screenAssistant, title: "Show it as", keywords: ["screen assistant", "mode"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Show it as")),

            // Color Picker
            SettingsSearchEntry(tab: .colorPicker, title: "Use Color Picker", keywords: ["color picker", "eyedropper"], highlightID: SettingsTab.colorPicker.highlightID(for: "Use Color Picker")),
            SettingsSearchEntry(tab: .colorPicker, title: "Button in the notch", keywords: ["color icon", "toolbar"], highlightID: SettingsTab.colorPicker.highlightID(for: "Button in the notch")),
            SettingsSearchEntry(tab: .colorPicker, title: "Show it as", keywords: ["color", "list"], highlightID: SettingsTab.colorPicker.highlightID(for: "Show it as")),
            SettingsSearchEntry(tab: .colorPicker, title: "Every colour format", keywords: ["hex", "hsl", "color formats"], highlightID: SettingsTab.colorPicker.highlightID(for: "Every colour format")),

            // Terminal
            SettingsSearchEntry(tab: .terminal, title: "Use Terminal", keywords: ["terminal", "guake", "shell"], highlightID: SettingsTab.terminal.highlightID(for: "Use Terminal")),
            SettingsSearchEntry(tab: .agents, title: "Command-line tools", keywords: ["cli", "claude", "codex", "gemini", "cursor", "opencode", "aider", "copilot", "ollama", "install", "start", "launcher", "terminal"], highlightID: SettingsTab.agents.highlightID(for: "Command-line tools")),
            SettingsSearchEntry(tab: .agents, title: "Approval card at the top right", keywords: ["approve", "allow", "deny", "permission", "card", "popup", "floating"], highlightID: SettingsTab.agents.highlightID(for: "Approval card at the top right")),
            SettingsSearchEntry(tab: .agents, title: "Tab size", keywords: ["agents", "size", "large", "bigger", "text"], highlightID: SettingsTab.agents.highlightID(for: "Tab size")),
            SettingsSearchEntry(tab: .agents, title: "AI Agents", keywords: ["agents","ai","claude","approve","permission"], highlightID: SettingsTab.agents.highlightID(for: "AI Agents")),
            SettingsSearchEntry(tab: .agents, title: "Connect an agent", keywords: ["claude code","codex","cursor","gemini","hooks","connect","approve"], highlightID: SettingsTab.agents.highlightID(for: "Connect an agent")),
            SettingsSearchEntry(tab: .agents, title: "Open new tasks in", keywords: ["terminal","iterm","new task","start agent"], highlightID: SettingsTab.agents.highlightID(for: "Open new tasks in")),
            SettingsSearchEntry(tab: .agents, title: "Wait for an answer in the notch", keywords: ["approval","timeout","wait"], highlightID: SettingsTab.agents.highlightID(for: "Wait for an answer in the notch")),
            SettingsSearchEntry(tab: .agents, title: "Ask in the agent's window when it is in front", keywords: ["terminal","front","approval"], highlightID: SettingsTab.agents.highlightID(for: "Ask in the agent's window when it is in front")),
            SettingsSearchEntry(tab: .agents, title: "Show working agents under the closed notch", keywords: ["status","working","closed notch"], highlightID: SettingsTab.agents.highlightID(for: "Show working agents under the closed notch")),
            SettingsSearchEntry(tab: .agents, title: "notchflow command", keywords: ["cli","command line","notchflow ask","notify","script"], highlightID: SettingsTab.agents.highlightID(for: "notchflow command")),
            SettingsSearchEntry(tab: .glance, title: "Use Glance", keywords: ["glance", "peek", "board", "dashboard", "widgets", "overlay", "hold"], highlightID: SettingsTab.glance.highlightID(for: "Use Glance")),
            SettingsSearchEntry(tab: .glance, title: "Hold to glance", keywords: ["glance", "shortcut", "hold", "key", "peek", "fn", "shift", "toggle", "release", "opens with"], highlightID: SettingsTab.glance.highlightID(for: "Hold to glance")),
            SettingsSearchEntry(tab: .glance, title: "Layouts", keywords: ["glance", "layout", "arrange", "drag", "preset", "grid"], highlightID: SettingsTab.glance.highlightID(for: "Layouts")),
            SettingsSearchEntry(tab: .glance, title: "Displays", keywords: ["glance", "monitor", "display", "screen", "second screen", "external"], highlightID: SettingsTab.glance.highlightID(for: "Displays")),
            SettingsSearchEntry(tab: .glance, title: "Panels", keywords: ["glance", "web page", "pdf", "calendar", "reminders", "clocks", "world clock", "promises", "stocks", "shares", "live window", "app window"], highlightID: SettingsTab.glance.highlightID(for: "Panels")),
            SettingsSearchEntry(tab: .glance, title: "Open web pages in", keywords: ["glance", "browser", "chrome", "chrome beta", "safari", "edge", "brave", "sign in", "login"], highlightID: SettingsTab.glance.highlightID(for: "Open web pages in")),
            SettingsSearchEntry(tab: .glance, title: "Hide ads and cookie banners", keywords: ["glance", "ads", "cookies", "block", "web"], highlightID: SettingsTab.glance.highlightID(for: "Hide ads and cookie banners")),
            SettingsSearchEntry(tab: .orbit, title: "Use Orbit", keywords: ["orbit", "projects", "people", "second brain", "memory", "timeline"], highlightID: SettingsTab.orbit.highlightID(for: "Use Orbit")),
            SettingsSearchEntry(tab: .orbit, title: "Best focus hours", keywords: ["orbit", "focus", "deep work", "energy", "best hours", "block", "scattered", "distracted", "switching"], highlightID: SettingsTab.orbit.highlightID(for: "Best focus hours")),
            SettingsSearchEntry(tab: .orbit, title: "Bills and renewals", keywords: ["orbit", "bill", "subscription", "renewal", "trial", "payment", "due"], highlightID: SettingsTab.orbit.highlightID(for: "Bills and renewals")),
            SettingsSearchEntry(tab: .orbit, title: "Morning brief", keywords: ["orbit", "brief", "morning", "daily", "summary", "today"], highlightID: SettingsTab.orbit.highlightID(for: "Morning brief")),
            SettingsSearchEntry(tab: .orbit, title: "Scenes", keywords: ["orbit", "scene", "deep work", "setup", "workspace", "focus", "agent"], highlightID: SettingsTab.orbit.highlightID(for: "Scenes")),
            SettingsSearchEntry(tab: .orbit, title: "Linear", keywords: ["orbit", "linear", "issues", "tickets", "api key", "loops", "inbox"], highlightID: SettingsTab.orbit.highlightID(for: "Linear")),
            SettingsSearchEntry(tab: .orbit, title: "Obsidian vault", keywords: ["orbit", "obsidian", "vault", "markdown", "notes", "daily note", "journal"], highlightID: SettingsTab.orbit.highlightID(for: "Obsidian vault")),
            SettingsSearchEntry(tab: .optimizer, title: "Batch and slow the timers", keywords: ["optimizer", "battery", "cpu", "timers", "energy", "wake ups"], highlightID: SettingsTab.optimizer.highlightID(for: "Batch and slow the timers")),
            SettingsSearchEntry(tab: .optimizer, title: "React to events instead of polling", keywords: ["optimizer", "polling", "events", "cpu", "energy"], highlightID: SettingsTab.optimizer.highlightID(for: "React to events instead of polling")),
            SettingsSearchEntry(tab: .optimizer, title: "Pause when nobody's looking", keywords: ["optimizer", "idle", "locked", "sleep", "pause", "battery"], highlightID: SettingsTab.optimizer.highlightID(for: "Pause when nobody's looking")),
            SettingsSearchEntry(tab: .optimizer, title: "Save battery on battery power", keywords: ["optimizer", "battery", "low power mode", "visualizer", "lyrics"], highlightID: SettingsTab.optimizer.highlightID(for: "Save battery on battery power")),
            SettingsSearchEntry(tab: .optimizer, title: "Calm endless animations", keywords: ["optimizer", "animations", "gpu", "pulse"], highlightID: SettingsTab.optimizer.highlightID(for: "Calm endless animations")),
            SettingsSearchEntry(tab: .optimizer, title: "Keep memory in check", keywords: ["optimizer", "memory", "ram", "cache"], highlightID: SettingsTab.optimizer.highlightID(for: "Keep memory in check")),
            SettingsSearchEntry(tab: .productivity, title: "Track where my time goes", keywords: ["time tracking", "hours", "apps", "screen time", "rescuetime", "productivity"], highlightID: SettingsTab.productivity.highlightID(for: "Track where my time goes")),
            SettingsSearchEntry(tab: .productivity, title: "Tell websites apart", keywords: ["browser", "sites", "youtube", "time tracking"], highlightID: SettingsTab.productivity.highlightID(for: "Tell websites apart")),
            SettingsSearchEntry(tab: .productivity, title: "Daily work goal", keywords: ["goal", "ring", "hours", "work"], highlightID: SettingsTab.productivity.highlightID(for: "Daily work goal")),
            SettingsSearchEntry(tab: .productivity, title: "Show the work ring under the closed notch", keywords: ["ring", "goal", "closed notch"], highlightID: SettingsTab.productivity.highlightID(for: "Show the work ring under the closed notch")),
            SettingsSearchEntry(tab: .productivity, title: "Weekly report on Friday afternoon", keywords: ["report", "week", "summary"], highlightID: SettingsTab.productivity.highlightID(for: "Weekly report on Friday afternoon")),
            SettingsSearchEntry(tab: .productivity, title: "Project names", keywords: ["projects", "clients", "invoice", "csv"], highlightID: SettingsTab.productivity.highlightID(for: "Project names")),
            SettingsSearchEntry(tab: .productivity, title: "Keep track of promises", keywords: ["promise", "commitment", "follow up", "whatsapp", "remind"], highlightID: SettingsTab.productivity.highlightID(for: "Keep track of promises")),
            SettingsSearchEntry(tab: .productivity, title: "Window stash", keywords: ["stash", "park", "windows", "hide", "clean desk", "flow"], highlightID: SettingsTab.productivity.highlightID(for: "Window stash")),
            SettingsSearchEntry(tab: .productivity, title: "Drag windows into the notch to stash them", keywords: ["drag", "drop", "stash", "notch", "window"], highlightID: SettingsTab.productivity.highlightID(for: "Drag windows into the notch to stash them")),
            SettingsSearchEntry(tab: .productivity, title: "See what I send in Messages", keywords: ["imessage", "sms", "messages", "plan", "promise", "sent", "full disk access"], highlightID: SettingsTab.productivity.highlightID(for: "See what I send in Messages")),
            SettingsSearchEntry(tab: .productivity, title: "Understand any language", keywords: ["hindi", "gujarati", "marathi", "hinglish", "gujlish", "ai", "promise", "language"], highlightID: SettingsTab.productivity.highlightID(for: "Understand any language")),
            SettingsSearchEntry(tab: .productivity, title: "Also track what others promise me", keywords: ["waiting on", "promise", "follow up"], highlightID: SettingsTab.productivity.highlightID(for: "Also track what others promise me")),
            SettingsSearchEntry(tab: .productivity, title: "Remind me", keywords: ["promise", "nudge", "reminder"], highlightID: SettingsTab.productivity.highlightID(for: "Remind me")),
            SettingsSearchEntry(tab: .productivity, title: "Workspaces", keywords: ["workspace", "setup", "launch apps", "layout", "work mode", "study"], highlightID: SettingsTab.productivity.highlightID(for: "Workspaces")),
            SettingsSearchEntry(tab: .productivity, title: "Suggest workspaces", keywords: ["workspace", "suggestions", "learn"], highlightID: SettingsTab.productivity.highlightID(for: "Suggest workspaces")),
            SettingsSearchEntry(tab: .productivity, title: "Done for the day quits workspace apps", keywords: ["done for the day", "quit", "workspace"], highlightID: SettingsTab.productivity.highlightID(for: "Done for the day quits workspace apps")),
            SettingsSearchEntry(tab: .smartTools, title: "Distraction meter", keywords: ["pomodoro", "focus", "youtube", "distraction", "off track"], highlightID: SettingsTab.smartTools.highlightID(for: "Distraction meter")),
            SettingsSearchEntry(tab: .smartTools, title: "Copy-to-action", keywords: ["clipboard", "copy", "tracking", "calendar", "directions"], highlightID: SettingsTab.smartTools.highlightID(for: "Copy-to-action")),
            SettingsSearchEntry(tab: .media, title: "Spotify search", keywords: ["spotify", "search", "connect", "client id", "api", "play"], highlightID: SettingsTab.media.highlightID(for: "Spotify search")),
            SettingsSearchEntry(tab: .media, title: "Artwork glow", keywords: ["glow", "album art", "artwork", "music"], highlightID: SettingsTab.media.highlightID(for: "Artwork glow")),
            SettingsSearchEntry(tab: .media, title: "Music first", keywords: ["music", "closed notch", "live activity", "priority", "agents", "spotify"], highlightID: SettingsTab.media.highlightID(for: "Music first")),
            SettingsSearchEntry(tab: .smartTools, title: "AI provider", keywords: ["minimax", "openai", "chatgpt", "claude", "anthropic", "gemini", "groq", "openrouter", "deepseek", "mistral", "grok", "ollama", "lm studio", "custom", "model", "api key"], highlightID: SettingsTab.smartTools.highlightID(for: "AI provider")),
            SettingsSearchEntry(tab: .smartTools, title: "Smart replies", keywords: ["minimax", "ai", "reply", "suggestions", "api key", "hinglish"], highlightID: SettingsTab.smartTools.highlightID(for: "Smart replies")),
            SettingsSearchEntry(tab: .smartTools, title: "People pins", keywords: ["shelf", "whatsapp", "favourites", "send file"], highlightID: SettingsTab.smartTools.highlightID(for: "People pins")),
            SettingsSearchEntry(tab: .smartTools, title: "Build watcher", keywords: ["github", "actions", "ci", "deploy", "terminal", "build"], highlightID: SettingsTab.smartTools.highlightID(for: "Build watcher")),
            SettingsSearchEntry(tab: .whatsapp, title: "Use WhatsApp", keywords: ["whatsapp", "messages", "chat", "reply", "qr", "link"], highlightID: SettingsTab.whatsapp.highlightID(for: "Use WhatsApp")),
            SettingsSearchEntry(tab: .whatsapp, title: "Mute groups", keywords: ["whatsapp", "groups", "mute", "mention"], highlightID: SettingsTab.whatsapp.highlightID(for: "Mute groups")),
            SettingsSearchEntry(tab: .whatsapp, title: "Mark as read when I open a conversation", keywords: ["whatsapp", "read receipts", "blue ticks"], highlightID: SettingsTab.whatsapp.highlightID(for: "Mark as read when I open a conversation")),
            SettingsSearchEntry(tab: .whatsapp, title: "Another account", keywords: ["whatsapp", "second account", "personal", "business", "two accounts", "multiple"], highlightID: SettingsTab.whatsapp.highlightID(for: "Another account")),
            SettingsSearchEntry(tab: .terminal, title: "Tell me when a command finishes", keywords: ["terminal", "notify", "notification", "command", "finished", "done", "build"], highlightID: SettingsTab.terminal.highlightID(for: "Tell me when a command finishes")),
            SettingsSearchEntry(tab: .terminal, title: "Open in", keywords: ["terminal", "iterm", "iterm2", "ghostty", "warp", "open in", "external"], highlightID: SettingsTab.terminal.highlightID(for: "Open in")),
            SettingsSearchEntry(tab: .terminal, title: "Shell path", keywords: ["shell", "zsh", "bash", "terminal"], highlightID: SettingsTab.terminal.highlightID(for: "Shell path")),
            SettingsSearchEntry(tab: .terminal, title: "Font size", keywords: ["terminal", "font", "text size"], highlightID: SettingsTab.terminal.highlightID(for: "Font size")),
            SettingsSearchEntry(tab: .terminal, title: "Terminal opacity", keywords: ["terminal", "opacity", "transparency", "blur", "background"], highlightID: SettingsTab.terminal.highlightID(for: "Terminal opacity")),
            SettingsSearchEntry(tab: .terminal, title: "Maximum height", keywords: ["terminal", "height", "size"], highlightID: SettingsTab.terminal.highlightID(for: "Maximum height")),
            SettingsSearchEntry(tab: .terminal, title: "Background color", keywords: ["terminal", "background", "color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Background color")),
            SettingsSearchEntry(tab: .terminal, title: "Foreground color", keywords: ["terminal", "foreground", "text color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Foreground color")),
            SettingsSearchEntry(tab: .terminal, title: "Cursor color", keywords: ["terminal", "cursor", "caret", "color"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor color")),
            SettingsSearchEntry(tab: .terminal, title: "Bold as bright", keywords: ["terminal", "bold", "bright", "colors"], highlightID: SettingsTab.terminal.highlightID(for: "Bold as bright")),
            SettingsSearchEntry(tab: .terminal, title: "Cursor style", keywords: ["terminal", "cursor", "block", "underline", "bar", "blink"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor style")),
            SettingsSearchEntry(tab: .terminal, title: "Scrollback lines", keywords: ["terminal", "scrollback", "buffer", "history"], highlightID: SettingsTab.terminal.highlightID(for: "Scrollback lines")),
            SettingsSearchEntry(tab: .terminal, title: "Option as Meta", keywords: ["terminal", "option", "meta", "alt", "key"], highlightID: SettingsTab.terminal.highlightID(for: "Option as Meta")),
            SettingsSearchEntry(tab: .terminal, title: "Mouse reporting", keywords: ["terminal", "mouse", "reporting", "vim", "tmux"], highlightID: SettingsTab.terminal.highlightID(for: "Mouse reporting")),
        ]
    }

    private func isTabVisible(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .timer, .stats, .clipboard, .screenAssistant, .colorPicker, .shelf, .notes, .terminal:
            return !enableMinimalisticUI
        default:
            return true
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsForm(tab: .general) {
                GeneralSettings()
            }
        case .tabsAndFeatures:
            SettingsForm(tab: .tabsAndFeatures) {
                NotchTabsSettingsView { destination in
                    if let target = SettingsTab(rawValue: destination), availableTabs.contains(target) {
                        selectedTab = target
                    }
                }
            }
        case .communications:
            SettingsForm(tab: .communications) {
                CommunicationsSettingsView()
            }
        case .liveActivities:
            SettingsForm(tab: .liveActivities) {
                LiveActivitiesSettings()
            }
        case .appearance:
            SettingsForm(tab: .appearance) {
                Appearance()
            }
        case .lockScreen:
            SettingsForm(tab: .lockScreen) {
                LockScreenSettings()
            }
        case .media:
            SettingsForm(tab: .media) {
                Media()
            }
        case .devices:
            SettingsForm(tab: .devices) {
                DevicesSettingsView()
            }
        case .timer:
            SettingsForm(tab: .timer) {
                TimerSettings()
            }
        case .calendar:
            SettingsForm(tab: .calendar) {
                CalendarSettings()
            }
        case .hudAndOSD:
            SettingsForm(tab: .hudAndOSD) {
                HUDAndOSDSettingsView()
            }
        case .battery:
            SettingsForm(tab: .battery) {
                Charge()
            }
        case .stats:
            SettingsForm(tab: .stats) {
                StatsSettings()
            }
        case .clipboard:
            SettingsForm(tab: .clipboard) {
                ClipboardSettings()
            }
        case .screenAssistant:
            SettingsForm(tab: .screenAssistant) {
                ScreenAssistantSettings()
            }
        case .colorPicker:
            SettingsForm(tab: .colorPicker) {
                ColorPickerSettings()
            }
        case .downloads:
            SettingsForm(tab: .downloads) {
                Downloads()
            }
        case .shelf:
            SettingsForm(tab: .shelf) {
                Shelf()
            }
        case .shortcuts:
            SettingsForm(tab: .shortcuts) {
                Shortcuts()
            }
        case .notes:
            SettingsForm(tab: .notes) {
                NotesSettingsView()
            }
        case .terminal:
            SettingsForm(tab: .terminal) {
                TerminalSettings()
            }
        case .whatsapp:
            SettingsForm(tab: .whatsapp) {
                WhatsAppSettings()
            }
        case .smartTools:
            SettingsForm(tab: .smartTools) {
                SmartToolsSettings()
            }
        case .productivity:
            SettingsForm(tab: .productivity) {
                ProductivitySettings()
            }
        case .optimizer:
            SettingsForm(tab: .optimizer) {
                OptimizerSettings()
            }
        case .glance:
            SettingsForm(tab: .glance) {
                GlanceSettings()
            }
        case .orbit:
            SettingsForm(tab: .orbit) {
                OrbitSettings()
            }
        case .agents:
            SettingsForm(tab: .agents) {
                AgentsSettings()
            }
        case .about:
            if let controller = updaterController {
                SettingsForm(tab: .about) {
                    About(updaterController: controller)
                }
            } else {
                SettingsForm(tab: .about) {
                    About(updaterController: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
                }
            }
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showMinimalisticBatteryIndicator) var showMinimalisticBatteryIndicator
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.musicGestureBehavior) var musicGestureBehavior
    @Default(.reverseSwipeGestures) var reverseSwipeGestures
    @Default(.reverseScrollGestures) var reverseScrollGestures
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover

    private func highlightID(_ title: String) -> String {
        SettingsTab.general.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableMinimalisticUI) {
                    Text("Enable Minimalistic UI")
                }
                .onChange(of: enableMinimalisticUI) { _, newValue in
                    if newValue {
                        // Auto-enable simpler animation mode
                        Defaults[.useModernCloseAnimation] = true
                    }
                }
                .settingsHighlight(id: highlightID("Enable Minimalistic UI"))

                Defaults.Toggle(key: .showMinimalisticBatteryIndicator) {
                    Text("Show battery indicator")
                }
                .disabled(!enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Show battery indicator in Minimalistic UI"))

                Defaults.Toggle(key: .showBatteryPercentInside) {
                    Text("Show battery percentage inside icon")
                }
                .disabled(!enableMinimalisticUI || !Defaults[.showMinimalisticBatteryIndicator])
                .settingsHighlight(id: highlightID("Show battery percentage inside icon"))
            } header: {
                Text("Layout")
            } footer: {
                Text("Minimalistic mode focuses on media controls and system HUDs, hiding all extra features for a clean, focused experience. Automatically enables simpler animations.")
            }

            Section {
                Defaults.Toggle(key: .menubarIcon) {
                    Text("Menubar icon")
                }
                .settingsHighlight(id: highlightID("Menubar icon"))
                LaunchAtLogin.Toggle {
                    Text("Launch at login")
                }
                .settingsHighlight(id: highlightID("Launch at login"))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Show on all displays"))
                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("Show on a specific display"))
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("Automatically switch displays"))
                Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                    Text("Hide Dynamic Island during screenshots & recordings")
                }
                .settingsHighlight(id: highlightID("Hide Dynamic Island during screenshots & recordings"))
            } header: {
                Text("Menu bar and displays")
            }

            Section {
                Picker(selection: $notchHeightMode, label:
                        Text("Notch display height")) {
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                        .onChange(of: notchHeightMode) {
                            switch notchHeightMode {
                            case .matchRealNotchSize:
                                notchHeight = 38
                            case .matchMenuBar:
                                notchHeight = 44
                            case .custom:
                                notchHeight = 38
                            }
                            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                        }
                        .settingsHighlight(id: highlightID("Notch display height"))
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Closed notch height")
            }

            NotchBehaviour()

            gestureControls()
        }
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            .disabled(!openNotchOnHover)
            .settingsHighlight(id: highlightID("Enable gestures"))
            if enableGestures {
                Defaults.Toggle(key: .enableHorizontalMusicGestures) {
                    Text("Media change with horizontal gestures")
                }
                .settingsHighlight(id: highlightID("Horizontal media gestures"))

                if enableHorizontalMusicGestures {
                    Picker("Gesture skip behavior", selection: $musicGestureBehavior) {
                        ForEach(MusicSkipBehavior.allCases) { behavior in
                            Text(behavior.displayName)
                                .tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Gesture skip behavior"))

                    Text(musicGestureBehavior.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Defaults.Toggle(key: .reverseSwipeGestures) {
                        Text("Reverse swipe gestures")
                    }
                    .settingsHighlight(id: highlightID("Reverse swipe gestures"))
                }

                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                .settingsHighlight(id: highlightID("Close gesture"))
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(Defaults[.gestureSensitivity] == 100 ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low")
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .reverseScrollGestures) {
                    Text("Reverse open/close scroll gestures")
                }
                .settingsHighlight(id: highlightID("Reverse scroll gestures"))
            }
        } header: {
            HStack {
                Text("Gestures")
                customBadge(text: "Beta")
            }
        } footer: {
            Text("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            NotchOpensOnSettings()
                .settingsHighlight(id: highlightID("Opens on"))
        } header: {
            Text("When the notch opens")
        }

        Section {
            SettingsToggle(key: .openNotchOnHover, title: "Open on hover", highlightID: highlightID("Open notch on hover"))
            if openNotchOnHover {
                LabeledContent {
                    HStack(spacing: 8) {
                        Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1)
                            .frame(width: 160)
                            .labelsHidden()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                } label: {
                    Text("Hover delay")
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            SettingsToggle(key: .enableNotchPeek, title: "Peek before opening",
                           detail: "A one-line preview while you hover: timer, music, next meeting, unread messages.",
                           highlightID: highlightID("Peek before opening"))
            SettingsToggle(key: .extendHoverArea, title: "Bigger hover area", highlightID: highlightID("Extend hover area"))
            SettingsToggle(key: .enableHaptics, title: "Haptic feedback", highlightID: highlightID("Enable haptics"))
        } header: {
            Text("Opening")
        }

        Section {
            Picker(selection: $externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { style in
                    Text(style.localizedName).tag(style)
                }
            } label: {
                SettingsRowLabel(title: "Style on displays without a notch", detail: externalDisplayStyle.description)
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("External display style"))
            SettingsToggle(key: .hideNonNotchUntilHover, title: "Hide until hovered",
                           detail: "On displays without a notch, it slides away until you hover over it.",
                           highlightID: highlightID("Hide until hovered"))
        } header: {
            Text("Other displays")
        }
    }
}

struct Charge: View {
    @ObservedObject private var batteryStatusViewModel = BatteryStatusViewModel.shared
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) private var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) private var showLowBatteryHUD
    @Default(.showFullBatteryHUD) private var showFullBatteryHUD
    @Default(.chargingBatteryHUDDuration) private var chargingBatteryHUDDuration
    @Default(.lowBatteryHUDDuration) private var lowBatteryHUDDuration
    @Default(.fullBatteryHUDDuration) private var fullBatteryHUDDuration
    @Default(.lowBatteryHUDThreshold) private var lowBatteryHUDThreshold
    @Default(.fullBatteryHUDThreshold) private var fullBatteryHUDThreshold
    @Default(.lowBatteryHUDStyle) private var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) private var fullBatteryHUDStyle

    private func highlightID(_ title: String) -> String {
        SettingsTab.battery.highlightID(for: title)
    }

    private var chargingDurationBinding: Binding<Double> {
        Binding(
            get: { Double(chargingBatteryHUDDuration) },
            set: { chargingBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDDuration) },
            set: { lowBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var fullBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDDuration) },
            set: { fullBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDThreshold) },
            set: { lowBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private var fullBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDThreshold) },
            set: { fullBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private func sectionOpacity(_ isEnabled: Bool) -> Double {
        isEnabled ? 1 : 0.5
    }

    var body: some View {
        Form {
            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .showBatteryIndicator) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))
                    Defaults.Toggle(key: .showPowerStatusNotifications) {
                        Text("Show power status notifications")
                    }
                    .settingsHighlight(id: highlightID("Show power status notifications"))
                    Defaults.Toggle(key: .playLowBatteryAlertSound) {
                        Text("Play low battery alert sound")
                    }
                    .settingsHighlight(id: highlightID("Play low battery alert sound"))
                } header: {
                    Text("General")
                }
                Section {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Show battery percentage")
                    }
                    .settingsHighlight(id: highlightID("Show battery percentage"))
                    Defaults.Toggle(key: .showPowerStatusIcons) {
                        Text("Show power status icons")
                    }
                    .settingsHighlight(id: highlightID("Show power status icons"))
                } header: {
                    Text("Battery Information")
                }
                Section {
                    Defaults.Toggle(key: .showChargingBatteryHUD) {
                        Text("Charging HUD")
                    }
                    .settingsHighlight(id: highlightID("Charging HUD"))

                    Defaults.Toggle(key: .showLowBatteryHUD) {
                        Text("Low battery HUD")
                    }
                    .settingsHighlight(id: highlightID("Low battery HUD"))

                    Defaults.Toggle(key: .showFullBatteryHUD) {
                        Text("Fully charged HUD")
                    }
                    .settingsHighlight(id: highlightID("Fully charged HUD"))
                } header: {
                    Text("Battery HUDs")
                } footer: {
                    Text("These temporary HUDs recreate the charging, low-battery, and full-battery notch alerts.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Charging duration")
                            Spacer()
                            Text("\(chargingBatteryHUDDuration)s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: chargingDurationBinding, in: 1...10, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Charging duration"))
                    .disabled(!showPowerStatusNotifications || !showChargingBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showChargingBatteryHUD))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Low battery duration")
                            Spacer()
                            Text("\(lowBatteryHUDDuration)s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: lowBatteryDurationBinding, in: 1...10, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Low battery duration"))
                    .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showLowBatteryHUD))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Full battery duration")
                            Spacer()
                            Text("\(fullBatteryHUDDuration)s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: fullBatteryDurationBinding, in: 1...10, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Full battery duration"))
                    .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showFullBatteryHUD))
                } header: {
                    Text("HUD Duration")
                }
                Section {
                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .charging)
                    } label: {
                        Label("Test charging HUD", systemImage: "bolt.fill")
                    }
                    .disabled(!showPowerStatusNotifications || !showChargingBatteryHUD)

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .lowBattery)
                    } label: {
                        Label("Test low battery HUD", systemImage: "battery.25")
                    }
                    .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .fullBattery)
                    } label: {
                        Label("Test full battery HUD", systemImage: "battery.100")
                    }
                    .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                } header: {
                    Text("HUD Tests")
                } footer: {
                    Text("Runs the real notch animation on the current target display. If an external screen is using Dynamic Island mode, the battery HUD is sent there first.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Low battery style", selection: $lowBatteryHUDStyle) {
                            ForEach(BatteryNotificationStyle.allCases) { style in
                                Text(style.title)
                                    .tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Compact matches the charging HUD. Standard uses the expanded DynamicNotch-style card.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Low battery style"))


                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Low battery threshold")
                            Spacer()
                            Text("\(lowBatteryHUDThreshold)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: lowBatteryThresholdBinding, in: 5...30, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Low battery threshold"))
                } header: {
                    Text("Low Battery")
                }
                .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showLowBatteryHUD))

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Full battery style", selection: $fullBatteryHUDStyle) {
                            ForEach(BatteryNotificationStyle.allCases) { style in
                                Text(style.title)
                                    .tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Compact keeps the alert inline. Standard uses the taller full-charge HUD with the charging animation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Full battery style"))


                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Full charge threshold")
                            Spacer()
                            Text("\(fullBatteryHUDThreshold)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: fullBatteryThresholdBinding, in: 80...100, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Full charge threshold"))
                } header: {
                    Text("Full Battery")
                }
                .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showFullBatteryHUD))
            } else {
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        Image(systemName: "battery.100percent.slash")
                            .font(.title)
                        Text("Battery settings and informations are only available on MacBooks")
                            .font(.title3)
                    }
                }
            }
        }
        .navigationTitle("Battery")
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle

    private func highlightID(_ title: String) -> String {
        SettingsTab.downloads.highlightID(for: title)
    }

    var body: some View {
        SwiftUI.Form {
            Section {
                Defaults.Toggle(key: .enableDownloadListener) {
                    Text("Enable download detection")
                }
                .settingsHighlight(id: highlightID("Enable download detection"))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download indicator style")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 16) {
                        DownloadStyleButton(
                            style: .progress,
                            isSelected: selectedDownloadIndicatorStyle == .progress,
                            disabled: !Defaults[.enableDownloadListener]
                        ) {
                            selectedDownloadIndicatorStyle = .progress
                        }

                        DownloadStyleButton(
                            style: .circle,
                            isSelected: selectedDownloadIndicatorStyle == .circle,
                            disabled: !Defaults[.enableDownloadListener]
                        ) {
                            selectedDownloadIndicatorStyle = .circle
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Download indicator style"))
            } header: {
                Text("Download Detection")
            } footer: {
                Text("Monitor your Downloads folder for Chromium-style downloads (.crdownload files) and show a live activity in the Dynamic Island while downloads are in progress.")
            }
        }
        .navigationTitle("Download Alerts")
    }

    struct DownloadStyleButton: View {
        let style: DownloadIndicatorStyle
        let isSelected: Bool
        let disabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    if style == .progress {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    } else {
                        SpinningCircleDownloadView()
                    }
                }
                .frame(width: 80, height: 60)
                .onHover { hovering in
                    if !disabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                    }
                }

                Text(style.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled {
                    action()
                }
            }
            .opacity(disabled ? 0.5 : 1.0)
        }

        private var backgroundColor: Color {
            if disabled { return Color(nsColor: .controlBackgroundColor) }
            if isSelected { return Color.accentColor.opacity(0.1) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private func setup() {
        // Ensure controllers are active
        SystemVolumeController.shared.start()
        SystemBrightnessController.shared.start()
        SystemKeyboardBacklightController.shared.start()

        // Initial state from volume
        let vol = SystemVolumeController.shared.currentVolume
        self.level = vol
        if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
        else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
        else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
        else { self.iconName = "speaker.wave.3.fill" }

        // Listeners
        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let vol = info["value"] as? Float {
                    self.level = vol
                    if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
                    else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
                    else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
                    else { self.iconName = "speaker.wave.3.fill" }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = "sun.max.fill"
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = val > 0.5 ? "light.max" : "light.min"
                }
            }
            .store(in: &cancellables)
    }
}

private struct HUDAndOSDSettingsView: View {
    @State private var selectedTab: Tab = {
        if Defaults[.enableSystemHUD] { return .hud }
        if Defaults[.enableCustomOSD] { return .osd }
        if Defaults[.enableVerticalHUD] { return .vertical }
        if Defaults[.enableCircularHUD] { return .circular }
        return .hud
    }()
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableVerticalHUD) var enableVerticalHUD
    @Default(.enableCircularHUD) var enableCircularHUD
    @Default(.verticalHUDPosition) var verticalHUDPosition
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.verticalHUDShowValue) var verticalHUDShowValue
    @Default(.verticalHUDInteractive) var verticalHUDInteractive
    @Default(.verticalHUDHeight) var verticalHUDHeight
    @Default(.verticalHUDWidth) var verticalHUDWidth
    @Default(.verticalHUDPadding) var verticalHUDPadding
    @Default(.verticalHUDUseAccentColor) var verticalHUDUseAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant

    // Circular HUD Props
    @Default(.circularHUDShowValue) var circularHUDShowValue
    @Default(.circularHUDSize) var circularHUDSize
    @Default(.circularHUDStrokeWidth) var circularHUDStrokeWidth
    @Default(.circularHUDUseAccentColor) var circularHUDUseAccentColor
    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case hud = "Dynamic Island HUD"
        case osd = "Custom OSD"
        case vertical = "Vertical Bar"
        case circular = "Circular"

        var id: String { rawValue }
    }

    private var paneBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var availableVerticalMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var verticalLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(verticalHUDLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                verticalHUDLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                HUDSelectionCard(
                    title: String(localized: "Dynamic Island"),
                    isSelected: selectedTab == .hud,
                    action: {
                        selectedTab = .hud
                        enableSystemHUD = true
                        enableCustomOSD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    VStack {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 64, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            .overlay {
                                HStack(spacing: 6) {
                                    Image(systemName: previewModel.iconName)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 12)

                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(Color.white.opacity(0.2))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white)
                                                    .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                    .animation(.spring(response: 0.3), value: previewModel.level)
                                            }
                                    }
                                    .frame(height: 4)
                                }
                                .padding(.horizontal, 8)
                            }
                    }
                }

                HUDSelectionCard(
                    title: String(localized: "Custom OSD"),
                    isSelected: selectedTab == .osd,
                    action: {
                        selectedTab = .osd
                        enableCustomOSD = true
                        enableSystemHUD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))

                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary)
                                                .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                .animation(.spring(response: 0.3), value: previewModel.level)
                                        }
                                }
                                .frame(width: 36, height: 4)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
                .settingsHighlight(id: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD"))

                HUDSelectionCard(
                    title: String(localized: "Vertical Bar"),
                    isSelected: selectedTab == .vertical,
                    action: {
                        selectedTab = .vertical
                        enableVerticalHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack {
                                GeometryReader { geo in
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white)
                                            .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                            .animation(.spring(response: 0.3), value: previewModel.level)
                                    }
                                }
                                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(.bottom, 2)

                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(previewModel.level > 0.15 ? .black : .secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(4)
                        }
                        .frame(width: 22, height: 54)
                }

                HUDSelectionCard(
                    title: String(localized: "Circular"),
                    isSelected: selectedTab == .circular,
                    action: {
                        selectedTab = .circular
                        enableCircularHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableVerticalHUD = false
                    }
                ) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(previewModel.level))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.3), value: previewModel.level)
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.top, 8)

            switch selectedTab {
            case .hud:
                HUD()
            case .osd:
                if #available(macOS 15.0, *) {
                    CustomOSDSettings()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(SettingsPalette.warn)

                        Text("macOS 15 or later required")
                            .font(.headline)

                        Text("Custom OSD feature requires macOS 15 or later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            case .vertical:
                Form {
                    if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                        Section {
                            SettingsPermissionCallout(
                                message: "Accessibility permission is needed to intercept system controls for the Vertical HUD.",
                                requestAction: {
                                    accessibilityPermission.requestAuthorizationPrompt()
                                },
                                openSettingsAction: {
                                    accessibilityPermission.openSystemSettings()
                                }
                            )
                        } header: {
                            Text("Accessibility")
                        }
                    }

                    if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                        Section {
                            Toggle("Volume HUD", isOn: $enableVolumeHUD)
                            Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                            Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                                .disabled(enableThirdPartyDDCIntegration)
                                .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active — brightness keys are handled by the external app." : "")
                        } header: {
                            Text("Controls")
                        } footer: {
                            Text("Choose which system controls should display HUD notifications.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Toggle("Show Percentage", isOn: $verticalHUDShowValue)
                        Toggle("Use Accent Color", isOn: $verticalHUDUseAccentColor)
                        Toggle("Interactive (Drag to Change)", isOn: $verticalHUDInteractive)
                        Picker("Material", selection: $verticalHUDMaterial) {
                            ForEach(availableVerticalMaterials, id: \.self) { material in
                                Text(material.rawValue).tag(material)
                            }
                        }

                        if verticalHUDMaterial == .liquid {
                            if #available(macOS 26.0, *) {
                                Picker("Glass mode", selection: $verticalHUDLiquidGlassCustomizationMode) {
                                    ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Custom liquid variant")
                                            Spacer()
                                            Text("v\(verticalHUDLiquidGlassVariant.rawValue)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(value: verticalLiquidVariantBinding, in: liquidVariantRange, step: 1)
                                    }
                                }
                            } else {
                                Text("Custom Liquid is available on macOS 26 or later.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                            Text("Color-coded Volume")
                        }
                        if Defaults[.useColorCodedVolumeDisplay] {
                            Defaults.Toggle(key: .useSmoothColorGradient) {
                                Text("Smooth color transitions")
                            }
                        }
                    } header: {
                        Text("Behavior & Style")
                    }

                    Section {
                        Picker("HUD Position", selection: $verticalHUDPosition) {
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.menu)

                        VStack(alignment: .leading) {
                            Text("Screen Padding: \(Int(verticalHUDPadding))px")
                            Slider(value: $verticalHUDPadding, in: 0...100, step: 4)
                        }
                    } header: {
                        Text("Position")
                    } footer: {
                        Text("Choose directly on which side of the screen the vertical bar appears.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Width: \(Int(verticalHUDWidth))px")
                            Slider(value: $verticalHUDWidth, in: 24...80, step: 2)
                        }
                        VStack(alignment: .leading) {
                            Text("Height: \(Int(verticalHUDHeight))px")
                            Slider(value: $verticalHUDHeight, in: 100...500, step: 10)
                        }
                        Button("Reset to Default") {
                            verticalHUDWidth = 36
                            verticalHUDHeight = 160
                            verticalHUDPadding = 24
                        }
                    } header: {
                        Text("Dimensions")
                    }
                }

            case .circular:
                Form {
                    if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                        Section {
                            SettingsPermissionCallout(
                                message: "Accessibility permission is needed to intercept system controls for the Circular HUD.",
                                requestAction: {
                                    accessibilityPermission.requestAuthorizationPrompt()
                                },
                                openSettingsAction: {
                                    accessibilityPermission.openSystemSettings()
                                }
                            )
                        } header: {
                            Text("Accessibility")
                        }
                    }

                    if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                        Section {
                            Toggle("Volume HUD", isOn: $enableVolumeHUD)
                            Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                            Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                                .disabled(enableThirdPartyDDCIntegration)
                                .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active — brightness keys are handled by the external app." : "")
                        } header: {
                            Text("Controls")
                        } footer: {
                            Text("Choose which system controls should display HUD notifications.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Toggle("Show Percentage", isOn: $circularHUDShowValue)
                        Toggle("Use Accent Color", isOn: $circularHUDUseAccentColor)
                        Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                            Text("Color-coded Volume")
                        }
                        if Defaults[.useColorCodedVolumeDisplay] {
                            Defaults.Toggle(key: .useSmoothColorGradient) {
                                Text("Smooth color transitions")
                            }
                        }
                    } header: {
                        Text("Style")
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Size: \(Int(circularHUDSize))px")
                            Slider(value: $circularHUDSize, in: 40...200, step: 5)
                        }
                        VStack(alignment: .leading) {
                            Text("Line Width: \(Int(circularHUDStrokeWidth))px")
                            Slider(value: $circularHUDStrokeWidth, in: 2...16, step: 1)
                        }
                        Button("Reset to Default") {
                            circularHUDSize = 65
                            circularHUDStrokeWidth = 4
                        }
                    } header: {
                        Text("Dimensions")
                    }
                }
            }

            // Third-party display integrations (shared across all HUD variants)
            ExternalDisplayIntegrationsSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(paneBackgroundColor)
        .navigationTitle("Controls")
        .onAppear {
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalHUDLiquidGlassCustomizationMode = .standard
            }
        }
    }
}

// MARK: - External Display Integrations Settings Section

private struct ExternalDisplayIntegrationsSection: View {
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return "Running" }
            if betterDisplayManager.isDetected { return "Not running" }
            return "Not detected"
        case .lunar:
            if lunarManager.isConnected { return "Connected" }
            if lunarManager.isRunning { return "Running" }
            if lunarManager.isDetected { return "Not running" }
            return "Not detected"
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if lunarManager.isRunning { return .orange }
            if lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return "Install [BetterDisplay](https://betterdisplay.pro) to control external display brightness (and optional volume) through NotchFlow's HUD."
            }
            if !betterDisplayManager.isRunning {
                return "BetterDisplay is installed but not currently running. Launch BetterDisplay to enable integration."
            }
            return "BetterDisplay OSD events will be routed through NotchFlow's active HUD style. Brightness is always routed; volume is routed when external volume control listener is enabled below. Make sure BetterDisplay's OSD integration is enabled in Settings › Application › Integration."
        case .lunar:
            if !lunarManager.isDetected {
                return "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast, and optional volume through NotchFlow's HUD via DDC."
            }
            if !lunarManager.isRunning {
                return "Lunar is installed but not currently running. Launch Lunar to enable integration."
            }
            if lunarManager.isConnected {
                return "Connected to Lunar's DDC socket. Brightness and contrast adjustments are shown through NotchFlow's HUD; volume follows when external volume control listener is enabled below."
            }
            return "Lunar is running but the socket connection is not yet established. It will connect automatically."
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: $volumeStepPercent, in: 1...25) {
                    HStack {
                        Text("Volume step")
                        Spacer()
                        Text("\(volumeStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume step"))
                .disabled(enableExternalVolumeControlListener)

                Stepper(value: $volumeFineStepPercent, in: 1...25) {
                    HStack {
                        Text("Volume fine step")
                        Spacer()
                        Text("\(volumeFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume fine step"))
                .disabled(enableExternalVolumeControlListener)

                if enableExternalVolumeControlListener {
                    Text("Disabled while external display volume integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $brightnessStepPercent, in: 1...25) {
                    HStack {
                        Text("Brightness step")
                        Spacer()
                        Text("\(brightnessStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness step"))
                .disabled(enableThirdPartyDDCIntegration)

                Stepper(value: $brightnessFineStepPercent, in: 1...25) {
                    HStack {
                        Text("Brightness fine step")
                        Spacer()
                        Text("\(brightnessFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness fine step"))
                .disabled(enableThirdPartyDDCIntegration)

                if enableThirdPartyDDCIntegration {
                    Text("Disabled while external display brightness integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Step size")
            } footer: {
                Text("Percent change per key press. Fine step applies when holding Shift+Option.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Enable third-party DDC app integration", isOn: $enableThirdPartyDDCIntegration)
                    .settingsHighlight(id: highlightID("Third-party DDC app integration"))

                if enableThirdPartyDDCIntegration {
                    Picker("Provider", selection: $thirdPartyDDCProvider) {
                        ForEach(ThirdPartyDDCProvider.allCases) { provider in
                            HStack {
                                AppIconImage(
                                    bundleIdentifiers: provider.bundleIdentifiers,
                                    symbolFallback: "display",
                                    symbolColor: .secondary
                                )
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .settingsHighlight(id: highlightID("Third-party DDC provider"))

                    Toggle("Enable external volume control listener", isOn: $enableExternalVolumeControlListener)
                        .settingsHighlight(id: highlightID("Enable external volume control listener"))

                    Text(
                        enableExternalVolumeControlListener
                        ? "NotchFlow's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                        : "NotchFlow keeps native volume key interception. External provider volume payloads are ignored while this is off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(providerStatusText)
                            .font(.caption)
                            .foregroundStyle(providerStatusColor)
                    }

                    Text(providerStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("Refresh detection", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                } else {
                    Text("Enable to route BetterDisplay or Lunar display adjustments through NotchFlow's active HUD style.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if enableThirdPartyDDCIntegration {
                    Text("NotchFlow always listens to selected-provider brightness events, and listens to provider volume events only when external volume listener is enabled.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

private struct HUDSelectionCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    preview
                }
                .frame(width: 110, height: 80)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct DevicesSettingsView: View {
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.useBluetoothHUD3DIcon) private var useBluetoothHUD3DIcon

    private func highlightID(_ title: String) -> String {
        SettingsTab.devices.highlightID(for: title)
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) {
                    Text("Show Bluetooth device connections")
                }
                .settingsHighlight(id: highlightID("Show Bluetooth device connections"))
                Defaults.Toggle(key: .useCircularBluetoothBatteryIndicator) {
                    Text("Use circular battery indicator")
                }
                .settingsHighlight(id: highlightID("Use circular battery indicator"))
                Defaults.Toggle(key: .showBluetoothBatteryPercentageText) {
                    Text("Show battery percentage text in HUD")
                }
                .settingsHighlight(id: highlightID("Show battery percentage text in HUD"))
                Defaults.Toggle(key: .showBluetoothDeviceNameMarquee) {
                    Text("Scroll device name in HUD")
                }
                .settingsHighlight(id: highlightID("Scroll device name in HUD"))
                Defaults.Toggle(key: .showAirPodsListeningModeChanges) {
                    Text("Show AirPods listening mode changes")
                }
                .settingsHighlight(id: highlightID("Show AirPods listening mode changes"))
                VStack(alignment: .leading, spacing: 12) {
                    Text("HUD icon style")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        BluetoothHUDIconStyleCard(
                            style: .symbol,
                            isSelected: !useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = false
                        }
                        BluetoothHUDIconStyleCard(
                            style: .threeD,
                            isSelected: useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = true
                        }
                        Spacer(minLength: 0)
                    }
                }
                .settingsHighlight(id: highlightID("Use 3D Bluetooth HUD icon"))
            } header: {
                Text("Bluetooth Audio Devices")
            } footer: {
                Text("Displays a HUD notification when Bluetooth audio devices (headphones, AirPods, speakers) connect, showing device name and battery level.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedBatteryDisplay) {
                    Text("Color-coded battery display")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Color-coded battery display"))
            } header: {
                Text("Battery Indicator Styling")
            } footer: {
                if progressBarStyle == .segmented {
                    Text("Color-coded fills are unavailable in Segmented mode. Switch to Hierarchical or Gradient inside Controls › Dynamic Island to adjust advanced options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill. Adjust gradient behavior from Controls › Dynamic Island.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Devices")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission lets Dynamic Island replace the native volume, brightness, and keyboard HUDs.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }



            if enableSystemHUD && !Defaults[.enableCustomOSD] && (hasAccessibilityPermission || enableThirdPartyDDCIntegration) {
                Section {
                    Toggle("Volume HUD", isOn: $enableVolumeHUD)
                    Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                    Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                        .disabled(enableThirdPartyDDCIntegration)
                        .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active \u{2014} brightness keys are handled by the external app." : "")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display HUD notifications.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Defaults.Toggle(key: .playVolumeChangeFeedback) {
                    Text("Play feedback when volume is changed")
                }
                .settingsHighlight(id: highlightID("Play feedback when volume is changed"))
                .help("Plays the supplied feedback clip whenever you press the hardware volume keys.")
            } header: {
                Text("Audio feedback")
            } footer: {
                Text("Requires Accessibility permission so Dynamic Island can intercept the hardware volume keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                    Text("Color-coded volume display")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Color-coded volume display"))

                if !colorCodingDisabled && (Defaults[.useColorCodedBatteryDisplay] || Defaults[.useColorCodedVolumeDisplay]) {
                    Defaults.Toggle(key: .useSmoothColorGradient) {
                        Text("Smooth color transitions")
                    }
                    .settingsHighlight(id: highlightID("Smooth color transitions"))
                }

                Defaults.Toggle(key: .showProgressPercentages) {
                    Text("Show percentages beside progress bars")
                }
                .settingsHighlight(id: highlightID("Show percentages beside progress bars"))
            } header: {
                Text("Dynamic Island Progress Bars")
            } footer: {
                if colorCodingDisabled {
                    Text("Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .settingsHighlight(id: highlightID("HUD style"))
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.progressBarStyle] = .hierarchical
                        }
                    }
                }
                Picker("Progressbar style", selection: $progressBarStyle) {
                    Text("Hierarchical")
                        .tag(ProgressBarStyle.hierarchical)
                    Text("Gradient")
                        .tag(ProgressBarStyle.gradient)
                    Text("Segmented")
                        .tag(ProgressBarStyle.segmented)
                }
                .settingsHighlight(id: highlightID("Progressbar style"))
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                .settingsHighlight(id: highlightID("Enable glowing effect"))
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Use accent color")
                }
                .settingsHighlight(id: highlightID("Use accent color"))
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .navigationTitle("Controls")
        .onAppear {
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableSystemHUD = false
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.showSneakPeekOnTrackChange) private var showSneakPeekOnTrackChange
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicAlbumParallaxEnabled) private var lockScreenMusicAlbumParallaxEnabled
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var lockScreenMusicFullscreenArtworkEnabled
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.visualizerBarCount) private var visualizerBarCount
    @Default(.enableWaveformScrubber) private var enableWaveformScrubber
    @Default(.colorExtractionMode) private var colorExtractionMode
    @Default(.parallaxEffectIntensity) private var parallaxEffectIntensity

    
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.media.highlightID(for: title)
    }

    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls && !enableMinimalisticUI
    }

    var body: some View {
        Form {
            Section {
                Picker("Music source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.localizedName).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
                .settingsHighlight(id: highlightID("Music source"))
                SpotifyConnectRow()
                    .settingsHighlight(id: highlightID("Spotify search"))
            } header: {
                Text("Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack(spacing: 4) {
                        Text("YouTube Music needs this free app:")
                        Link("github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                    }
                } else {
                    Text("Now Playing works with every music app. Scrubbing may not work in apps that don't support it, like Amazon Music.")
                }
            }

            if mediaController == .spotify {
                SpotifyAuthSettingsSection()
            }

            Section {
                SettingsToggle(key: .showStandardMediaControls, title: "Music player",
                               detail: "The player in the open notch.",
                               highlightID: highlightID("Music player"))
                    .disabled(enableMinimalisticUI)
                if enableMinimalisticUI {
                    SettingsStatus(text: "Minimal mode is on, so the player is hidden. Turn it off in Appearance.", kind: .warn)
                } else if showStandardMediaControls {
                    SettingsToggle(key: .autoHideInactiveNotchMediaPlayer, title: "Hide it when nothing plays",
                                   detail: "Off keeps the player showing, even with nothing playing.",
                                   highlightID: highlightID("Hide it when nothing plays"))
                        .padding(.leading, 16)
                }
                SettingsToggle(key: .musicArtworkGlow, title: "Artwork glow",
                               detail: "A soft glow of the album colours behind the art.",
                               highlightID: highlightID("Artwork glow"))
                SettingsToggle(key: .showLiveCanvasInDynamicIsland, title: "Moving artwork",
                               detail: "Shows the song's video artwork when the app has one, like Spotify Canvas.",
                               highlightID: highlightID("Moving artwork"))
                LabeledContent {
                    HStack {
                        Slider(value: $parallaxEffectIntensity, in: 0...12, step: 1).frame(maxWidth: 180)
                        Text("\(Int(parallaxEffectIntensity))").foregroundStyle(.secondary).monospacedDigit().frame(width: 24, alignment: .trailing)
                    }
                } label: {
                    SettingsRowLabel(title: "Artwork tilt", detail: "How much the art moves with the pointer.")
                }
                .settingsHighlight(id: highlightID("Artwork tilt"))
                SettingsToggle(key: .showShuffleAndRepeat, title: "Choose the buttons",
                               detail: "Pick and order the player's buttons, like shuffle and repeat.",
                               highlightID: highlightID("Choose the buttons"))
                if showShuffleAndRepeat {
                    SettingsToggle(key: .showMediaOutputControl, title: "Output button",
                                   detail: "Adds the AirPlay and speaker picker to the choices.",
                                   highlightID: highlightID("Output button"))
                        .padding(.leading, 16)
                    MusicSlotConfigurationView()
                }
            } header: {
                Text("Open notch")
            }

            Section {
                Toggle(isOn: $coordinator.musicLiveActivityEnabled.animation()) {
                    SettingsRowLabel(title: "Show music in the closed notch",
                                     detail: "Artwork on one side, a visualizer on the other.")
                }
                .disabled(standardControlsSuppressed)
                .settingsHighlight(id: highlightID("Show music in the closed notch"))
                if coordinator.musicLiveActivityEnabled {
                    SettingsToggle(key: .closedNotchMusicFirst, title: "Music first",
                                   detail: "While music plays it stays in front. Approvals, calls and messages still show for a moment.",
                                   highlightID: highlightID("Music first"))
                        .padding(.leading, 16)
                    SettingsToggle(key: .showSongMetadataInClosedNotch, title: "Song and artist on other displays",
                                   detail: "On screens without a notch, the title shows too.",
                                   highlightID: highlightID("Song and artist on other displays"))
                        .padding(.leading, 16)
                    SettingsToggle(key: .musicControlWindowEnabled, title: "Floating controls",
                                   detail: "Play, pause and skip beside the notch while music plays.",
                                   highlightID: highlightID("Floating controls"))
                        .padding(.leading, 16)
                        .disabled(standardControlsSuppressed)
                    if musicControlWindowEnabled {
                        Picker("Skip buttons", selection: $musicSkipBehavior) {
                            ForEach(MusicSkipBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.leading, 32)
                        .settingsHighlight(id: highlightID("Skip buttons"))
                    }
                }
                LabeledContent {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        Text("\(Int(waitInterval))s").foregroundStyle(.secondary).monospacedDigit()
                    }
                } label: {
                    SettingsRowLabel(title: "Hide after pausing", detail: "How long the closed notch keeps showing music after it stops.")
                }
            } header: {
                Text("Closed notch")
            }

            Section {
                SettingsToggle(key: .enableSneakPeek, title: "Sneak peek",
                               detail: "Opens the notch for a moment to show what changed.",
                               highlightID: highlightID("Sneak peek"))
                if enableSneakPeek {
                    SettingsToggle(key: .showSneakPeekOnTrackChange, title: "When the song changes")
                        .padding(.leading, 16)
                    Picker("Style", selection: $sneakPeekStyles) {
                        ForEach(SneakPeekStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .padding(.leading, 16)
                    .settingsHighlight(id: highlightID("Sneak peek style"))
                }
            } header: {
                Text("Sneak peek")
            }

            Section {
                SettingsToggle(key: .enableLyrics, title: "Lyrics",
                               detail: "A lyrics button in the Music tab.",
                               highlightID: highlightID("Lyrics"))
                SettingsToggle(key: .showLyricsUnderNotch, title: "Sing along under the closed notch",
                               detail: "While lyrics are on, the line being sung shows under the notch.")
                    .padding(.leading, 16)
                    .disabled(!Defaults[.enableLyrics])
            } header: {
                Text("Lyrics")
            }

            Section {
                SettingsToggle(key: .enableRealTimeWaveform, title: "Live visualizer",
                               detail: "Moves with the actual sound, not a loop.",
                               highlightID: highlightID("Live visualizer"))
                SettingsToggle(key: .coloredSpectrogram, title: "Colour it with the artwork",
                               highlightID: highlightID("Colour it with the artwork"))
                SettingsToggle(key: .enableWaveformScrubber, title: "Drag the waveform to scrub")
                Picker("Bars", selection: $visualizerBarCount) {
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                }
                .pickerStyle(.segmented)
                Picker("Artwork colours", selection: $colorExtractionMode) {
                    Text("Classic").tag(ColorExtractionMode.legacy)
                    Text("Vibrant").tag(ColorExtractionMode.vibrant)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Visualizer")
            } footer: {
                Text("The live visualizer needs macOS 14.2 or later and uses very little power.")
            }

            Section {
                Picker("Hide the notch in full screen", selection: $hideNotchOption) {
                    Text("Always").tag(HideNotchOption.always)
                    Text("When the music app is full screen").tag(HideNotchOption.nowPlayingOnly)
                    Text("Never").tag(HideNotchOption.never)
                }
                .onChange(of: hideNotchOption) {
                    Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
                }
                SettingsToggle(key: .lockScreenMusicAlbumParallaxEnabled, title: "Artwork tilt on the lock screen",
                               highlightID: highlightID("Artwork tilt on the lock screen"))
            } header: {
                Text("More")
            }
        }
        .navigationTitle("Music")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }

    private var unavailableBlurRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Only applies when Material is set to Frosted Glass.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var customLiquidBlurRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Custom liquid glass already renders with Apple's liquid material, so this option is managed automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    @Default(.reminderLeadTime) var reminderLeadTime
    @Default(.reminderSneakPeekDuration) var reminderSneakPeekDuration
    @Default(.enableLockScreenReminderWidget) var enableLockScreenReminderWidget
    @Default(.lockScreenReminderChipStyle) var lockScreenReminderChipStyle
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.showFullEventTitles) var showFullEventTitles
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
    @Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
    @Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
    @Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
    @Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
    @Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
    @Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
    @Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
    @Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
    @Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
    @Default(.enableThirdPartyCalendarApp) private var enableThirdPartyCalendarApp
    @Default(.selectedCalendarApp) private var selectedCalendarApp
    @Default(.fantasticalDefaultView) private var fantasticalDefaultView

    private func highlightID(_ title: String) -> String {
        SettingsTab.calendar.highlightID(for: title)
    }

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return "15 mins"
            case .mins30: return "30 mins"
            case .hour1: return "1 hour"
            case .hours3: return "3 hours"
            case .hours6: return "6 hours"
            case .hours12: return "12 hours"
            case .restOfDay: return "Rest of the day"
            case .allTime: return "All time"
            }
        }
    }

    var body: some View {
        Form {
            if !calendarManager.hasCalendarAccess || !calendarManager.hasReminderAccess {
                Section {
                    SettingsStatus(text: "NotchFlow can't see your calendar or reminders yet.", kind: .warn)
                    HStack {
                        Spacer()
                        Button("Open System Settings") {
                            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(settingsURL)
                            }
                        }
                        Button("Allow Access") {
                            Task {
                                await calendarManager.checkCalendarAuthorization()
                                await calendarManager.checkReminderAuthorization()
                            }
                        }
                        .settingsPrimaryButton()
                    }
                } header: {
                    Text("Access")
                }
            } else {
                Section {
                    SettingsToggle(key: .showCalendar, title: "Calendar tab",
                                   detail: "Today's and upcoming events in the notch.",
                                   highlightID: highlightID("Show calendar"))
                    if showCalendar {
                        Toggle(isOn: $showFullEventTitles) { SettingsRowLabel(title: "Show full event titles") }
                            .settingsHighlight(id: highlightID("Show full event titles"))
                        Toggle(isOn: $autoScrollToNextEvent) { SettingsRowLabel(title: "Scroll to the next event") }
                            .settingsHighlight(id: highlightID("Auto-scroll to next event"))
                        Toggle(isOn: $hideAllDayEvents) {
                            SettingsRowLabel(title: "Hide all-day events",
                                             detail: "Also hides them from the upcoming-reminder activity.")
                        }
                        .settingsHighlight(id: highlightID("Hide all-day events"))
                    }
                } header: {
                    Text("Calendar")
                }

                Section {
                    SettingsToggle(key: .enableRemindersFeature, title: "Todos tab",
                                   detail: "Your Apple Reminders lists in the notch: see and add todos.",
                                   highlightID: highlightID("Show Reminders tab"))
                    Toggle(isOn: $hideCompletedReminders) { SettingsRowLabel(title: "Hide completed todos") }
                        .settingsHighlight(id: highlightID("Hide completed reminders"))
                    SettingsToggle(key: .showTodayProgressRing, title: "Today's progress in the closed notch",
                                   detail: "A ring of today's todos done, when nothing else is showing.")
                } header: {
                    Text("Todos")
                }

                Section {
                    SettingsToggle(key: .enableMeetingCountdown, title: "Countdown and Join button",
                                   detail: "Five minutes before a Zoom, Meet, Teams or Webex meeting.")
                    SettingsToggle(key: .pauseMusicDuringMeetings, title: "Pause music during meetings",
                                   detail: "Resumes afterwards if NotchFlow paused it.")
                } header: {
                    Text("Meetings")
                }

                Section {
                    SettingsToggle(key: .enableReminderLiveActivity, title: "Upcoming reminders in the closed notch",
                                   highlightID: highlightID("Enable reminder live activity"))
                    if enableReminderLiveActivity {
                        Picker("Countdown style", selection: $reminderPresentationStyle) {
                            ForEach(ReminderPresentationStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Countdown style"))
                        LabeledContent("Show it before") {
                            HStack(spacing: 8) {
                                Slider(value: Binding(get: { Double(reminderLeadTime) }, set: { reminderLeadTime = Int($0) }),
                                       in: 1...60, step: 1)
                                    .frame(width: 180)
                                    .labelsHidden()
                                Text("\(reminderLeadTime) min").monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                        LabeledContent("Show it for") {
                            HStack(spacing: 8) {
                                Slider(value: $reminderSneakPeekDuration, in: 3...20, step: 1)
                                    .frame(width: 180)
                                    .labelsHidden()
                                Text("\(Int(reminderSneakPeekDuration)) s").monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("Upcoming reminders")
                }

                Section {
                    LabeledContent("Calendars") {
                        SettingsStatus(text: statusText(for: calendarManager.calendarAuthorizationStatus),
                                       kind: statusKind(for: calendarManager.calendarAuthorizationStatus))
                    }
                    LabeledContent("Reminders") {
                        SettingsStatus(text: statusText(for: calendarManager.reminderAuthorizationStatus),
                                       kind: statusKind(for: calendarManager.reminderAuthorizationStatus))
                    }
                } header: {
                    Text("Access")
                }

                // MARK: - Third-party Calendar Integration
                Section {
                    SettingsToggle(key: .enableThirdPartyCalendarApp, title: "Open events in another calendar app",
                                   detail: "Clicking an event opens it there instead of Apple Calendar.",
                                   highlightID: highlightID("Enable third-party calendar app launch"))
                    
                    if enableThirdPartyCalendarApp {
                        Picker("Calendar App", selection: $selectedCalendarApp) {
                            ForEach(ThirdPartyCalendarApp.allCases) { app in
                                HStack {
                                    AppIconImage(
                                        bundleIdentifiers: app.bundleIdentifiers,
                                        symbolFallback: app.fallbackIconName,
                                        symbolColor: app.fallbackIconColor
                                    )
                                    Text(app.displayName)
                                }
                                .tag(app)
                            }
                        }
                        .settingsHighlight(id: highlightID("Calendar App"))
                        
                        if selectedCalendarApp == .fantastical {
                            Picker("Default View", selection: $fantasticalDefaultView) {
                                ForEach(FantasticalViewStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .settingsHighlight(id: highlightID("Fantastical Default View"))
                        }
                    }
                } header: {
                    Text("Calendar app")
                }

                Section(header: Text("Calendars to show")) {
                    let grouped = Dictionary(grouping: calendarManager.allCalendars, by: \.accountName)
                    let sortedAccounts = grouped.keys.sorted()

                    ForEach(sortedAccounts, id: \.self) { account in
                        let accountCalendars = grouped[account] ?? []
                        let allAccountSelected = accountCalendars.allSatisfy { calendarManager.getCalendarSelected($0) }

                        Section(header: HStack {
                            Text(account)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { allAccountSelected },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarsSelected(accountCalendars, isSelected: isSelected)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(!showCalendar)
                        }) {
                            ForEach(accountCalendars, id: \.id) { calendar in
                                Toggle(isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(calendar.color))
                                            .frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                                .disabled(!showCalendar)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
        .navigationTitle("Calendar & Todos")
    }

    private func statusText(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess, .authorized: return String(localized: "Allowed")
        case .writeOnly: return String(localized: "Add only")
        case .denied: return String(localized: "Denied")
        case .restricted: return String(localized: "Restricted")
        case .notDetermined: return String(localized: "Not asked yet")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private func statusKind(for status: EKAuthorizationStatus) -> SettingsStatus.Kind {
        switch status {
        case .fullAccess, .authorized: return .ok
        case .writeOnly, .notDetermined: return .warn
        case .denied, .restricted: return .error
        @unknown default: return .neutral
        }
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()

                        // Channel badge
                        Text(UpdateChannel.buildChannel.displayName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(UpdateChannel.buildChannel.badgeColor).opacity(0.2))
                            .foregroundStyle(Color(UpdateChannel.buildChannel.badgeColor))
                            .clipShape(Capsule())

                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }

                Section {
                    Button("Say hello again") { HelloWindowController.shared.show() }
                }

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Text("GitHub")
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())

                if NotchFlowUpdates.isEnabled {
                    UpdaterSettingsView(updater: updaterController.updater)
                    Section {
                        Text("Updates come from NotchFlow's releases on GitHub (dhruvv620/notchflow). Use Check for Updates in the toolbar or the menu bar icon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("This is a local build from Build.command: update it with git pull and bash Build.command. Copies made with Release.command update themselves.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Updates")
                    }
                }
                VStack(spacing: 0) {
                    Divider()
                        .padding(.bottom, 5)
                    Text("NotchFlow by dhruvv620 · Free software under the GPL v3")
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 7)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            if NotchFlowUpdates.isEnabled {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        .navigationTitle("About")
    }
}

private extension DevicesSettingsView {
    enum BluetoothHUDIconStyle: String {
        case symbol
        case threeD

        var title: String {
            switch self {
            case .symbol:
                return "Symbol"
            case .threeD:
                return "3D"
            }
        }
    }

    struct BluetoothHUDIconStyleCard: View {
        let style: BluetoothHUDIconStyle
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    preview
                }
                .frame(width: 90, height: 64)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }

                Text(style.title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
            .onTapGesture { action() }
        }

        private var preview: some View {
            Group {
                switch style {
                case .symbol:
                    Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                case .threeD:
                    if let url = Bundle.main.url(
                        forResource: BluetoothAudioDeviceType.airpods.inlineHUDAnimationBaseName,
                        withExtension: "mov",
                        subdirectory: "BluetoothHUDAnimations"
                    ) ?? Bundle.main.url(
                        forResource: BluetoothAudioDeviceType.airpods.inlineHUDAnimationBaseName,
                        withExtension: "mov"
                    ) {
                        SettingsLoopingVideoIcon(url: url, size: CGSize(width: 28, height: 28))
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }

        private var backgroundColor: Color {
            if isSelected { return Color.accentColor.opacity(0.12) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

private struct SettingsLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: SettingsLoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = SettingsLoopingPlayerController(url: url, autoPlay: true)
            layer.player = controller?.player
        }
    }
}

private final class SettingsLoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL, autoPlay: Bool = true) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        if autoPlay {
            player.play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

struct Shelf: View {
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    @Default(.dynamicShelf) private var shelfOn
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.shelf.highlightID(for: title)
    }

    var body: some View {
        Form {
            if !shelfOn {
                Section {
                    Text("Off: no Shelf tab, and dropping files on the notch does nothing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                if !canEnableShelf || !fullDiskAccessPermission.isAuthorized {
                    Section {
                        if !canEnableShelf {
                            SettingsStatus(text: "Shelf can't read your files yet. Allow Documents and Downloads, or Full Disk Access.", kind: .warn)
                            HStack {
                                SettingsRowLabel(title: "Documents and Downloads")
                                Spacer()
                                Button("Open Privacy & Security") { shelfFolderAccessPermission.openSystemSettings() }
                                Button("Allow") { shelfFolderAccessPermission.requestAccessPrompt() }
                                    .settingsPrimaryButton()
                            }
                        }
                        if !fullDiskAccessPermission.isAuthorized {
                            HStack {
                                SettingsRowLabel(title: "Full Disk Access",
                                                 detail: "Lets Shelf take files from anywhere, not only Documents and Downloads.")
                                Spacer()
                                Button("Open Privacy & Security") { fullDiskAccessPermission.openSystemSettings() }
                                Button("Allow") { fullDiskAccessPermission.requestAccessPrompt() }
                            }
                        }
                    } header: {
                        Text("Access")
                    }
                }

                Section {
                    SettingsToggle(key: .openShelfByDefault, title: "Open the Shelf when files are added",
                                   highlightID: highlightID("Open shelf tab by default if items added"))
                    SettingsToggle(key: .copyOnDrag, title: "Copy instead of move",
                                   detail: "Dragging out of the Shelf leaves the original where it is.",
                                   highlightID: highlightID("Copy items on drag"))
                    SettingsToggle(key: .autoRemoveShelfItems, title: "Remove after dragging out",
                                   highlightID: highlightID("Remove from shelf after dragging"))
                } header: {
                    Text("Shelf")
                }

                Section {
                    Picker("Share with", selection: $quickShareProvider) {
                        ForEach(quickShareService.availableProviders, id: \.id) { provider in
                            HStack {
                                QuickShareProviderIconImage(provider: provider, size: 16)
                                Text(provider.id)
                            }
                            .tag(provider.id)
                        }
                    }
                    .settingsHighlight(id: highlightID("Quick Share Service"))
                } header: {
                    Text("Quick Share")
                } footer: {
                    Text("Files you drop on the share button go to \(selectedProvider?.id ?? "this service").")
                }

                if quickShareProvider == "LocalSend" {
                    LocalSendSettingsSection(highlightID: highlightID)
                }
            }
        }
        .navigationTitle("Shelf")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

// MARK: - LocalSend Settings Section

private struct LocalSendSettingsSection: View {
    let highlightID: (String) -> String
    
    @Default(.localSendDevicePickerGlassMode) private var glassMode
    @Default(.localSendDevicePickerLiquidGlassVariant) private var liquidGlassVariant
    
    var body: some View {
        Section {
            Picker("Device list style", selection: $glassMode) {
                ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .settingsHighlight(id: highlightID("Device Picker Style"))
            
            if glassMode == .customLiquid {
                Picker("Glass look", selection: $liquidGlassVariant) {
                    ForEach(LiquidGlassVariant.allCases) { variant in
                        Text("Variant \(variant.rawValue)").tag(variant)
                    }
                }
                .padding(.leading, 16)
            }
        } header: {
            Text("LocalSend")
        } footer: {
            Text("How the list of nearby devices looks when you drop files.")
        }
    }
}

struct LiveActivitiesSettings: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared

    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) var focusIndicatorNonPersistent
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                SettingsToggle(key: .enableScreenRecordingDetection, title: "Notice screen recording",
                               detail: "Knows when this Mac's screen is being recorded.",
                               highlightID: highlightID("Notice screen recording"))
                if enableScreenRecordingDetection {
                    SettingsToggle(key: .showRecordingIndicator, title: "Show a recording dot",
                                   highlightID: highlightID("Show a recording dot"))
                        .padding(.leading, 16)
                    if recordingManager.isMonitoring {
                        LabeledContent("Right now") {
                            if recordingManager.isRecording {
                                SettingsStatus(text: "Recording", kind: .error)
                            } else {
                                SettingsStatus(text: "Not recording", kind: .ok)
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
            } header: {
                Text("Screen recording")
            }

            Section {
                SettingsToggle(key: .enableDoNotDisturbDetection, title: "Notice Focus",
                               detail: "Shows when a Focus like Do Not Disturb turns on.",
                               highlightID: highlightID("Notice Focus"))
                if enableDoNotDisturbDetection {
                    SettingsToggle(key: .showDoNotDisturbIndicator, title: "Show the Focus icon",
                                   highlightID: highlightID("Show the Focus icon"))
                        .padding(.leading, 16)
                    SettingsToggle(key: .showDoNotDisturbLabel, title: "Show the Focus name",
                                   detail: focusIndicatorNonPersistent ? "Off while Focus only shows for a moment." : nil,
                                   highlightID: highlightID("Show the Focus name"))
                        .padding(.leading, 16)
                        .disabled(focusIndicatorNonPersistent)
                    SettingsToggle(key: .focusIndicatorNonPersistent, title: "Only for a moment",
                                   detail: "Shows Focus turning on or off, then hides it.",
                                   highlightID: highlightID("Only for a moment"))
                        .padding(.leading, 16)
                    if doNotDisturbManager.isMonitoring {
                        LabeledContent("Right now") {
                            if doNotDisturbManager.isDoNotDisturbActive {
                                SettingsStatus(text: doNotDisturbManager.currentFocusModeName.isEmpty ? "Focus on" : doNotDisturbManager.currentFocusModeName, kind: .ok)
                            } else {
                                SettingsStatus(text: "No Focus")
                            }
                        }
                        .padding(.leading, 16)
                    }
                    if !fullDiskAccessPermission.isAuthorized {
                        HStack {
                            SettingsRowLabel(title: "Your own Focus icons and colours",
                                             detail: "Needs Full Disk Access. Focus works without it.")
                            Spacer()
                            Button("Open Privacy & Security") { fullDiskAccessPermission.openSystemSettings() }
                            Button("Allow") { fullDiskAccessPermission.requestAccessPrompt() }
                                .settingsPrimaryButton()
                        }
                        .padding(.leading, 16)
                    }
                }
            } header: {
                Text("Focus")
            }

            Section {
                SettingsToggle(key: .enableCapsLockIndicator, title: "Show Caps Lock",
                               detail: "A small light in the notch while Caps Lock is on.",
                               highlightID: highlightID("Show Caps Lock"))
                if Defaults[.enableCapsLockIndicator] {
                    SettingsToggle(key: .showCapsLockLabel, title: "With the words \"Caps Lock\"",
                                   highlightID: highlightID("With the words Caps Lock"))
                        .padding(.leading, 16)
                    Picker("Colour", selection: $capsLockTintMode) {
                        ForEach(CapsLockIndicatorTintMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 16)
                    .settingsHighlight(id: highlightID("Caps Lock colour"))
                }
            } header: {
                Text("Caps Lock")
            }

            Section {
                SettingsToggle(key: .enableCameraDetection, title: "Camera in use",
                               detail: "A green dot while an app uses the camera.",
                               highlightID: highlightID("Camera in use"))
                SettingsToggle(key: .enableMicrophoneDetection, title: "Microphone in use",
                               detail: "An orange dot while an app uses the microphone.",
                               highlightID: highlightID("Microphone in use"))
                if privacyManager.isMonitoring {
                    LabeledContent("Right now") {
                        HStack(spacing: 12) {
                            SettingsStatus(text: privacyManager.cameraActive ? "Camera on" : "Camera off",
                                           kind: privacyManager.cameraActive ? .ok : .neutral)
                            SettingsStatus(text: privacyManager.microphoneActive ? "Microphone on" : "Microphone off",
                                           kind: privacyManager.microphoneActive ? .warn : .neutral)
                        }
                    }
                }
            } header: {
                Text("Camera and microphone")
            }
        }
        .navigationTitle("Live Activities")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
        }
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.selectedCameraID) var selectedCameraID
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.externalDisplayStyle) private var externalDisplayStyle

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.appearance.highlightID(for: title)
    }

    var body: some View {
        Form {
            NotchAppearanceSettingsSection(highlightID: highlightID)

            Section {
                Toggle("Always show the tab bar", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Settings button in the notch")
                }
                .settingsHighlight(id: highlightID("Settings icon in notch"))
                Defaults.Toggle(key: .enableShadow) {
                    Text("Shadow under the open notch")
                }
                .settingsHighlight(id: highlightID("Enable window shadow"))
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Round the top corners when open")
                        Text("Off keeps the top corners as tight as the closed notch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Round the top corners when open"))
            } header: {
                Text("Notch")
            }

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                Section {
                    Picker("Main screen style", selection: $externalDisplayStyle) {
                        ForEach(ExternalDisplayStyle.allCases) { style in
                            Text(style.localizedName)
                                .tag(style)
                        }
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Main screen style"))
                    Text(externalDisplayStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Display Style")
                }
            }

            notchWidthControls()

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable Dynamic mirror")
                }
                .disabled(!checkVideoInput())
                .settingsHighlight(id: highlightID("Enable Dynamic mirror"))
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .settingsHighlight(id: highlightID("Mirror shape"))
                
                if webcamManager.cameraAvailable {
                    Picker("Mirror Camera", selection: $selectedCameraID) {
                        ForEach(webcamManager.availableCameras, id: \.uniqueID) { device in
                            Text(device.localizedName)
                                .tag(device.uniqueID)
                        }
                    }
                    .onChange(of: selectedCameraID) { _, _ in
                        if Defaults[.showMirror] {
                            webcamManager.stopSession()
                            webcamManager.startSession()
                        }
                    }
                    .settingsHighlight(id: highlightID("Mirror Camera"))
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Idle Animation")
                }
                .settingsHighlight(id: highlightID("Idle Animation"))
            } header: {
                Text("Extras")
            }

            // MARK: - Custom Idle Animations Section
            IdleAnimationsSettingsSection()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        appIconCard(
                            title: "Default",
                            image: defaultAppIconImage(),
                            isSelected: selectedAppIconID == nil
                        ) {
                            selectedAppIconID = nil
                            applySelectedAppIcon()
                        }

                        ForEach(customAppIcons) { icon in
                            appIconCard(
                                title: icon.name,
                                image: customIconImage(for: icon),
                                isSelected: selectedAppIconID == icon.id.uuidString
                            ) {
                                selectedAppIconID = icon.id.uuidString
                                applySelectedAppIcon()
                            }
                            .contextMenu {
                                Button("Remove") {
                                    removeCustomIcon(icon)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(isIconDropTarget ? 0.18 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isIconDropTarget ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                        handleIconDrop(providers)
                    }

                    HStack(spacing: 8) {
                        Button("Add icon") {
                            iconImportError = nil
                            isIconImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Remove selected") {
                            if let id = selectedAppIconID,
                               let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                                removeCustomIcon(icon)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedAppIconID == nil)
                    }

                    if let iconImportError {
                        Text(iconImportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Drop a PNG, JPEG, TIFF, or ICNS file to add it to your icon library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("App icon"))
            } header: {
                HStack {
                    Text("App icon")
                }
            }
        }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = "Icon import was canceled or failed."
            }
        }
        .navigationTitle("Appearance")
    }

    private func defaultAppIconImage() -> NSImage? {
        let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
        return NSImage(named: fallbackName)
    }

    private func customIconImage(for icon: CustomAppIcon) -> NSImage? {
        NSImage(contentsOf: icon.fileURL)
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in importCustomIcon(from: url) }
        }
        return true
    }

    private func importCustomIcon(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            iconImportError = "That file could not be loaded as an image."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = "Unable to save the icon file."
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "Custom Icon" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        selectedAppIconID = newIcon.id.uuidString
        NSApp.applicationIconImage = image
        iconImportError = nil
    }

    private func removeCustomIcon(_ icon: CustomAppIcon) {
        if let index = customAppIcons.firstIndex(of: icon) {
            customAppIcons.remove(at: index)
        }
        if FileManager.default.fileExists(atPath: icon.fileURL.path) {
            try? FileManager.default.removeItem(at: icon.fileURL)
        }
        if selectedAppIconID == icon.id.uuidString {
            selectedAppIconID = nil
            applySelectedAppIcon()
        }
    }

    func checkVideoInput() -> Bool {
        if let _ = AVCaptureDevice.default(for: .video) {
            return true
        }

        return false
    }

    private func notchWidthControls() -> some View {
        Section {
            Defaults.Toggle(key: .customizePhysicalNotchWidth) {
                Text("Customize physical notch width")
            }
            .onChange(of: customizePhysicalNotchWidth) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("Customize physical notch width"))
            Slider(value: Binding(
                get: { Double(closedNotchWidth) },
                set: { closedNotchWidth = CGFloat($0); NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil) }
            ), in: 80...400, step: 5) {
                HStack {
                    Text("Closed notch / pill width")
                    Spacer()
                    Text("\(Int(closedNotchWidth)) pt").foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Closed notch / pill width"))
        } header: {
            Text("Closed Notch")
        }
    }
}

struct LockScreenSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var previewManager = LockScreenWidgetPreviewManager.shared
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicLiquidGlassVariant) private var lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var lockScreenMusicFullscreenArtworkEnabled
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.enableLockScreenWeatherWidget) private var enableLockScreenWeatherWidget
    @Default(.enableLockScreenFocusWidget) private var enableLockScreenFocusWidget
    @Default(.lockScreenWeatherWidgetStyle) private var lockScreenWeatherWidgetStyle
    @Default(.lockScreenWeatherProviderSource) private var lockScreenWeatherProviderSource
    @Default(.lockScreenWeatherTemperatureUnit) private var lockScreenWeatherTemperatureUnit
    @Default(.lockScreenBatteryShowsCharging) private var lockScreenWeatherShowsCharging
    @Default(.lockScreenBatteryShowsBatteryGauge) private var lockScreenWeatherShowsBatteryGauge
    @Default(.lockScreenWeatherShowsAQI) private var lockScreenWeatherShowsAQI
    @Default(.lockScreenWeatherShowsSunrise) private var lockScreenWeatherShowsSunrise
    @Default(.lockScreenWeatherAQIScale) private var lockScreenWeatherAQIScale
    @Default(.enableLockScreenReminderWidget) private var enableLockScreenReminderWidget
    @Default(.lockScreenReminderChipStyle) private var lockScreenReminderChipStyle
    @Default(.lockScreenReminderWidgetHorizontalAlignment) private var lockScreenReminderWidgetHorizontalAlignment
    @Default(.lockScreenReminderWidgetVerticalOffset) private var lockScreenReminderWidgetVerticalOffset
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
    @Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
    @Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
    @Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
    @Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
    @Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
    @Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
    @Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
    @Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
    @Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
    @Default(.lockScreenMusicMergedAirPlayOutput) private var lockScreenMusicMergedAirPlayOutput
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.lockScreen.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return "15 mins"
            case .mins30: return "30 mins"
            case .hour1: return "1 hour"
            case .hours3: return "3 hours"
            case .hours6: return "6 hours"
            case .hours12: return "12 hours"
            case .restOfDay: return "Rest of the day"
            case .allTime: return "All time"
            }
        }
    }

    private enum ReminderAlignmentOption: String, CaseIterable, Identifiable {
        case leading
        case center
        case trailing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .leading: return "Left"
            case .center: return "Center"
            case .trailing: return "Right"
            }
        }
    }

    private var musicVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenMusicLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenMusicLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableLockScreenLiveActivity) {
                    Text("Enable lock screen live activity")
                }
                .settingsHighlight(id: highlightID("Enable lock screen live activity"))
                Defaults.Toggle(key: .enableLockSounds) {
                    Text("Play lock/unlock sounds")
                }
                .settingsHighlight(id: highlightID("Play lock/unlock sounds"))
            } header: {
                Text("Live Activity & Feedback")
            } footer: {
                Text("Controls whether Dynamic Island mirrors lock/unlock events with its own live activity and audible chimes.")
            }

            Section {
                Button(previewManager.isPreviewVisible ? "Hide lock screen preview" : "Preview lock screen widgets") {
                    previewManager.togglePreview()
                }
                .buttonStyle(.borderedProminent)
                .settingsHighlight(id: highlightID("Preview lock screen widgets"))
            } header: {
                Text("Preview")
            } footer: {
                Text("Opens a transparent preview window with mock data that mirrors the current lock screen widget configuration.")
            }

            Section {
                if #available(macOS 26.0, *) {
                    Picker("Material", selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Material"))
                } else {
                    Picker("Material", selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .disabled(true)
                    .settingsHighlight(id: highlightID("Material"))
                    Text("Liquid Glass requires macOS 26 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if lockScreenGlassStyle == .liquid {
                    Picker("Glass mode", selection: $lockScreenGlassCustomizationMode) {
                        ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Glass mode"))

                    if lockScreenGlassCustomizationMode == .customLiquid {
                        Text("Use the sliders below to pick unique Apple liquid-glass variants for each widget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Custom Liquid settings require the Liquid Glass material.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Lock Screen Glass")
            } footer: {
                Text("Choose the global material mode for lock screen widgets. Custom Liquid unlocks per-widget variant sliders while Standard sticks to the classic frosted/liquid options.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text("Show lock screen media panel")
                }
                .settingsHighlight(id: highlightID("Show lock screen media panel"))
                Defaults.Toggle(key: .lockScreenShowAppIcon) {
                    Text("Show media app icon")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Show media app icon"))
                if isAppleMusicActive {
                    Defaults.Toggle(key: .lockScreenMusicMergedAirPlayOutput) {
                        Text("Show merged AirPlay and output devices")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Show merged AirPlay and output devices"))
                }
                Defaults.Toggle(key: .lockScreenPanelShowsBorder) {
                    Text("Show panel border")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Show panel border"))
                if lockScreenGlassCustomizationMode == .customLiquid {
                    Defaults.Toggle(key: .lockScreenMusicUsesEnhancedLiquidBorder) {
                        Text("Use enhanced liquid border")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Use enhanced liquid border"))
                }
                if lockScreenGlassCustomizationMode == .customLiquid {
                    variantSlider(
                        title: "Music panel variant",
                        value: musicVariantBinding,
                        currentValue: lockScreenMusicLiquidGlassVariant.rawValue,
                        isEnabled: enableLockScreenMediaWidget,
                        highlight: highlightID("Music panel variant")
                    )
                } else if lockScreenGlassStyle == .frosted {
                    Defaults.Toggle(key: .lockScreenPanelUsesBlur) {
                        Text("Enable media panel blur")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else {
                    blurSettingUnavailableRow
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Enable media panel blur"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Defaults.Toggle(key: .lockScreenMusicFullscreenArtworkEnabled) {
                        Text("Fullscreen artwork on right-click")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Fullscreen artwork on right-click"))
                    Defaults.Toggle(key: .lockScreenUseArtworkLayoutOverFullscreenCanvas) {
                        Text("Use album art layout over fullscreen canvas")
                    }
                    .disabled(!enableLockScreenMediaWidget || !lockScreenMusicFullscreenArtworkEnabled)
                    .settingsHighlight(id: highlightID("Use album art layout over fullscreen canvas"))
                    Defaults.Toggle(key: .lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork) {
                        Text("Keep album art visible during fullscreen artwork")
                    }
                    .disabled(!enableLockScreenMediaWidget || !lockScreenMusicFullscreenArtworkEnabled)
                    .settingsHighlight(id: highlightID("Keep album art visible during fullscreen artwork"))
                    Text("Right-click the album art on the lock screen to set it as the wallpaper. Right-click again or click the background to restore the original wallpaper. If a canvas is available, NotchFlow can also keep the same album art + player layout on top of the live canvas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !showStandardMediaControls {
                    Text("Enable Dynamic Island media controls to manage the lock screen panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Media Panel")
            } footer: {
                Text("Enable and style the media controls that appear above the system clock when the screen is locked.")
            }
            .disabled(!showStandardMediaControls)
            .opacity(showStandardMediaControls ? 1 : 0.5)

            Section {
                Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                    Text("Show lock screen timer")
                }
                .settingsHighlight(id: highlightID("Show lock screen timer"))
                Picker("Timer surface", selection: timerSurfaceBinding) {
                    ForEach(LockScreenTimerSurfaceMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableLockScreenTimerWidget)
                .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                .settingsHighlight(id: highlightID("Timer surface"))

                if timerGlassModeIsGlass {
                    Picker("Timer glass material", selection: $lockScreenTimerGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .disabled(!enableLockScreenTimerWidget)
                    .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                    .settingsHighlight(id: highlightID("Timer glass material"))

                    if lockScreenTimerGlassStyle == .liquid {
                        Picker("Timer liquid mode", selection: $lockScreenTimerGlassCustomizationMode) {
                            ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!enableLockScreenTimerWidget)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Timer liquid mode"))

                        if lockScreenTimerGlassCustomizationMode == .customLiquid {
                            variantSlider(
                                title: "Timer widget variant",
                                value: timerVariantBinding,
                                currentValue: lockScreenTimerLiquidGlassVariant.rawValue,
                                isEnabled: enableLockScreenTimerWidget,
                                highlight: highlightID("Timer widget variant")
                            )
                        }
                    } else {
                        Text("Uses the frosted blur treatment while glass mode is enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Classic mode keeps the original translucent black background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                }
            } header: {
                Text("Timer Widget")
            } footer: {
                Text("Controls the optional timer widget that floats above the media panel, including its classic, frosted, or liquid glass surface independent of the global material setting.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                    Text("Show lock screen weather")
                }
                .settingsHighlight(id: highlightID("Show lock screen weather"))

                if enableLockScreenWeatherWidget {
                    Picker("Layout", selection: $lockScreenWeatherWidgetStyle) {
                        ForEach(LockScreenWeatherWidgetStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Layout"))

                    Picker("Weather data provider", selection: $lockScreenWeatherProviderSource) {
                        ForEach(LockScreenWeatherProviderSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Weather data provider"))

                    Picker("Temperature unit", selection: $lockScreenWeatherTemperatureUnit) {
                        ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                            Text(unit.localizedName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Temperature unit"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsLocation) {
                        Text("Show location label")
                    }
                    .disabled(lockScreenWeatherWidgetStyle == .circular)
                    .settingsHighlight(id: highlightID("Show location label"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) {
                        Text("Show sunrise time")
                    }
                    .disabled(lockScreenWeatherWidgetStyle != .inline)
                    .settingsHighlight(id: highlightID("Show sunrise time"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsAQI) {
                        Text("Show AQI widget")
                    }
                    .disabled(!lockScreenWeatherProviderSource.supportsAirQuality)
                    .settingsHighlight(id: highlightID("Show AQI widget"))

                    if lockScreenWeatherShowsAQI && lockScreenWeatherProviderSource.supportsAirQuality {
                        Picker("Air quality scale", selection: $lockScreenWeatherAQIScale) {
                            ForEach(LockScreenWeatherAirQualityScale.allCases) { scale in
                                Text(scale.displayName).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Air quality scale"))
                    }

                    if !lockScreenWeatherProviderSource.supportsAirQuality {
                        Text("Air quality requires the Open Meteo provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) {
                        Text("Use colored gauges")
                    }
                    .settingsHighlight(id: highlightID("Use colored gauges"))
                }
            } header: {
                Text("Weather Widget")
            } footer: {
                Text("Enable the weather capsule and configure its layout, provider, units, and optional battery/AQI indicators.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenReminderWidget) {
                    Text("Show lock screen reminder")
                }
                .settingsHighlight(id: highlightID("Show lock screen reminder"))

                Picker("Chip color", selection: $lockScreenReminderChipStyle) {
                    ForEach(LockScreenReminderChipStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableLockScreenReminderWidget)
                .settingsHighlight(id: highlightID("Chip color"))

                Picker("Alignment", selection: $lockScreenReminderWidgetHorizontalAlignment) {
                    ForEach(ReminderAlignmentOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableLockScreenReminderWidget)
                .settingsHighlight(id: highlightID("Reminder alignment"))

                HStack {
                    Text("Vertical offset")
                    Slider(
                        value: $lockScreenReminderWidgetVerticalOffset,
                        in: -160...160,
                        step: 2
                    )
                    .disabled(!enableLockScreenReminderWidget)
                    Text("\(Int(lockScreenReminderWidgetVerticalOffset)) px")
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .settingsHighlight(id: highlightID("Reminder vertical offset"))
            } header: {
                Text("Reminder Widget")
            } footer: {
                Text("Controls the lock screen reminder chip and its positioning.")
            }

            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))

                    if lockScreenWeatherShowsBatteryGauge {
                        Defaults.Toggle(key: .lockScreenBatteryUsesLaptopSymbol) {
                            Text("Use MacBook icon when on battery")
                        }
                        .settingsHighlight(id: highlightID("Use MacBook icon when on battery"))

                        Defaults.Toggle(key: .lockScreenBatteryShowsCharging) {
                            Text("Show charging status")
                        }
                        .settingsHighlight(id: highlightID("Show charging status"))

                        if lockScreenWeatherShowsCharging {
                            Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) {
                                Text("Show charging percentage")
                            }
                            .settingsHighlight(id: highlightID("Show charging percentage"))
                        }

                        Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) {
                            Text("Show Bluetooth battery")
                        }
                        .settingsHighlight(id: highlightID("Show Bluetooth battery"))
                    }
                } header: {
                    Text("Battery Widget")
                } footer: {
                    Text("Enable the battery capsule and configure its layout.")
                }
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                    Text("Show focus widget")
                }
                .settingsHighlight(id: highlightID("Show focus widget"))
            } header: {
                Text("Focus Widget")
            } footer: {
                Text("Displays the current Focus state above the weather capsule whenever Focus detection is enabled.")
            }

            Section {
                Defaults.Toggle(key: .lockScreenShowCalendarEvent) {
                    Text("Show next calendar event")
                }
                .settingsHighlight(id: highlightID("Show next calendar event"))

                LabeledContent("Show events within the next") {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $lockScreenCalendarEventLookaheadWindow) {
                            ForEach(CalendarLookaheadOption.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show events within the next"))

                Toggle("Show events from all calendars", isOn: Binding(
                    get: { lockScreenCalendarSelectionMode == "all" },
                    set: { useAll in
                        if useAll {
                            lockScreenCalendarSelectionMode = "all"
                        } else {
                            lockScreenCalendarSelectionMode = "selected"
                            lockScreenSelectedCalendarIDs = Set(calendarManager.eventCalendars.map { $0.id })
                        }
                    }
                ))
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show events from all calendars"))

                if lockScreenCalendarSelectionMode != "all" {
                    HStack {
                        Spacer()
                        Button("Deselect All") {
                            lockScreenSelectedCalendarIDs = []
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(isOn: Binding(
                                get: { lockScreenSelectedCalendarIDs.contains(calendar.id) },
                                set: { isOn in
                                    if isOn {
                                        lockScreenSelectedCalendarIDs.insert(calendar.id)
                                    } else {
                                        lockScreenSelectedCalendarIDs.remove(calendar.id)
                                    }
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(calendar.color))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 2)
                    .disabled(!lockScreenShowCalendarEvent)
                }

                Defaults.Toggle(key: .lockScreenShowCalendarCountdown) {
                    Text("Show countdown")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show countdown"))

                Defaults.Toggle(key: .lockScreenShowCalendarEventEntireDuration) {
                    Text("Show event for entire duration")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show event for entire duration"))
                .onChange(of: Defaults[.lockScreenShowCalendarEventEntireDuration]) { _, newValue in
                    if newValue {
                        Defaults[.lockScreenShowCalendarEventAfterStartEnabled] = false
                    }
                }

                Defaults.Toggle(
                    "Hide active event and show next upcoming event",
                    key: .lockScreenShowCalendarEventAfterStartEnabled
                )
                .disabled(!lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration)
                .settingsHighlight(id: highlightID("Hide active event and show next upcoming event"))

                LabeledContent("Show event after it starts") {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $lockScreenShowCalendarEventAfterStartWindow) {
                            Text("1 min").tag("1m")
                            Text("5 mins").tag("5m")
                            Text("10 mins").tag("10m")
                            Text("15 mins").tag("15m")
                            Text("30 mins").tag("30m")
                            Text("45 mins").tag("45m")
                            Text("1 hour").tag("1h")
                            Text("2 hours").tag("2h")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .disabled(!lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration || !lockScreenShowCalendarEventAfterStartEnabled)

                Text("Turn off 'Show event for entire duration' to use the post-start duration option.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) {
                    Text("Show time remaining")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show time remaining"))

                Defaults.Toggle(key: .lockScreenShowCalendarStartTimeAfterBegins) {
                    Text("Show start time after event begins")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show start time after event begins"))
            } header: {
                Text("Calendar Widget")
            } footer: {
                Text("Displays your next upcoming calendar event above or below the weather capsule. Calendar selection here is independent from the Dynamic Island calendar filter.")
            }

            LockScreenPositioningControls()

            Section {
                Button("Copy Latest Crash Report") {
                    copyLatestCrashReport()
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Collect the latest crash report to share with the developer when reporting lock screen or overlay issues.")
            }
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .navigationTitle("Lock Screen")
    }
}

extension LockScreenSettings {
    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }

    private var blurSettingUnavailableRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Only available when Material is set to Frosted Glass.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func variantSlider(
        title: String,
        value: Binding<Double>,
        currentValue: Int,
        isEnabled: Bool,
        highlight: String,
        preview: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("v\(currentValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: liquidVariantRange, step: 1)

            if let preview {
                preview
                    .padding(.top, 6)
            }
        }
        .settingsHighlight(id: highlight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct LockScreenPositioningControls: View {
    @Default(.lockScreenWeatherVerticalOffset) private var weatherOffset
    @Default(.lockScreenMusicVerticalOffset) private var musicOffset
    @Default(.lockScreenTimerVerticalOffset) private var timerOffset
    @Default(.lockScreenMusicPanelWidth) private var musicWidth
    @Default(.lockScreenTimerWidgetWidth) private var timerWidth
    private let offsetRange: ClosedRange<Double> = -160...160
    private let musicWidthRange: ClosedRange<Double> = 320...Double(LockScreenMusicPanel.defaultCollapsedWidth)
    private let timerWidthRange: ClosedRange<Double> = 320...LockScreenTimerWidget.defaultWidth

    var body: some View {
        Section {
            let weatherBinding = Binding<Double>(
                get: { weatherOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if weatherOffset != clampedValue {
                        weatherOffset = clampedValue
                    }
                    propagateWeatherOffsetChange(animated: false)
                }
            )

            let timerBinding = Binding<Double>(
                get: { timerOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if timerOffset != clampedValue {
                        timerOffset = clampedValue
                    }
                    propagateTimerOffsetChange(animated: false)
                }
            )

            let musicBinding = Binding<Double>(
                get: { musicOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if musicOffset != clampedValue {
                        musicOffset = clampedValue
                    }
                    propagateMusicOffsetChange(animated: false)
                }
            )

            let musicWidthBinding = Binding<Double>(
                get: { musicWidth },
                set: { newValue in
                    let clampedValue = clamp(newValue, within: musicWidthRange)
                    if musicWidth != clampedValue {
                        musicWidth = clampedValue
                        propagateMusicWidthChange(animated: false)
                    }
                }
            )

            let timerWidthBinding = Binding<Double>(
                get: { timerWidth },
                set: { newValue in
                    let clampedValue = clamp(newValue, within: timerWidthRange)
                    if timerWidth != clampedValue {
                        timerWidth = clampedValue
                        propagateTimerWidthChange(animated: false)
                    }
                }
            )

            LockScreenPositioningPreview(
                weatherOffset: weatherBinding,
                timerOffset: timerBinding,
                musicOffset: musicBinding,
                musicWidth: musicWidthBinding,
                timerWidth: timerWidthBinding
            )
            .frame(height: 260)
            .padding(.vertical, 8)

            HStack(alignment: .top, spacing: 24) {
                offsetColumn(
                    title: String(localized: "Weather"),
                    value: weatherOffset,
                    resetTitle: String(localized: "Reset Weather"),
                    resetAction: resetWeatherOffset
                )

                Divider()
                    .frame(height: 64)

                offsetColumn(
                    title: String(localized: "Timer"),
                    value: timerOffset,
                    resetTitle: String(localized: "Reset Timer"),
                    resetAction: resetTimerOffset
                )

                Divider()
                    .frame(height: 64)

                offsetColumn(
                    title: String(localized: "Music"),
                    value: musicOffset,
                    resetTitle: String(localized: "Reset Music"),
                    resetAction: resetMusicOffset
                )

                Spacer()
            }

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 16) {
                widthSlider(
                    title: String(localized: "Media Panel Width"),
                    value: musicWidthBinding,
                    range: musicWidthRange,
                    resetTitle: String(localized: "Reset Media Width"),
                    resetAction: resetMusicWidth,
                    helpText: String(localized: "Shrinks the lock screen media panel while keeping the expanded view full width.")
                )

                widthSlider(
                    title: String(localized: "Timer Widget Width"),
                    value: timerWidthBinding,
                    range: timerWidthRange,
                    resetTitle: String(localized: "Reset Timer Width"),
                    resetAction: resetTimerWidth,
                    helpText: String(localized: "Adjusts the lock screen timer widget width without affecting button sizing.")
                )
            }
        } header: {
            Text("Lock Screen Positioning")
        } footer: {
            Text("Drag the previews to adjust vertical placement. Positive values lift the panel; negative values lower it. Use the width sliders below to narrow the media and timer widgets without exceeding their default size. Changes apply instantly while the widgets are visible.")
                .textCase(nil)
        }
    }

    private func clampOffset(_ value: Double) -> Double {
        min(max(value, offsetRange.lowerBound), offsetRange.upperBound)
    }

    private func clamp(_ value: Double, within range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func resetWeatherOffset() {
        weatherOffset = 0
        propagateWeatherOffsetChange(animated: true)
    }

    private func resetTimerOffset() {
        timerOffset = 0
        propagateTimerOffsetChange(animated: true)
    }

    private func resetMusicOffset() {
        musicOffset = 0
        propagateMusicOffsetChange(animated: true)
    }

    private func resetMusicWidth() {
        musicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
        propagateMusicWidthChange(animated: true)
    }

    private func resetTimerWidth() {
        timerWidth = LockScreenTimerWidget.defaultWidth
        propagateTimerWidthChange(animated: true)
    }

    private func propagateWeatherOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenWeatherPanelManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateTimerOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateMusicOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateMusicWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateTimerWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetPanelManager.shared.refreshPosition(animated: animated)
        }
    }

    @ViewBuilder
    private func offsetColumn(title: String, value: Double, resetTitle: String, resetAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) Offset")
                .font(.subheadline.weight(.semibold))

            Text("\(formattedPoints(value)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(resetTitle) {
                resetAction()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func widthSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        resetTitle: String,
        resetAction: @escaping () -> Void,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedWidth(value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)

            HStack(alignment: .top) {
                Button(resetTitle) {
                    resetAction()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func formattedPoints(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }

    private func formattedWidth(_ value: Double) -> String {
        String(format: "%.0f pt", value)
    }
}

private struct LockScreenPositioningPreview: View {
    @Binding var weatherOffset: Double
    @Binding var timerOffset: Double
    @Binding var musicOffset: Double
    @Binding var musicWidth: Double
    @Binding var timerWidth: Double

    @State private var weatherStartOffset: Double = 0
    @State private var timerStartOffset: Double = 0
    @State private var musicStartOffset: Double = 0
    @State private var isWeatherDragging = false
    @State private var isTimerDragging = false
    @State private var isMusicDragging = false

    private let offsetRange: ClosedRange<Double> = -160...160

    var body: some View {
        GeometryReader { geometry in
            let screenPadding: CGFloat = 26
            let screenCornerRadius: CGFloat = 28
            let screenRect = CGRect(
                x: screenPadding,
                y: screenPadding,
                width: geometry.size.width - (screenPadding * 2),
                height: geometry.size.height - (screenPadding * 2)
            )
            let centerX = screenRect.midX
            let weatherBaseY = screenRect.minY + (screenRect.height * 0.28)
            let timerBaseY = screenRect.minY + (screenRect.height * 0.5)
            let musicBaseY = screenRect.minY + (screenRect.height * 0.78)
            let weatherSize = CGSize(width: screenRect.width * 0.42, height: screenRect.height * 0.22)
            let defaultMusicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
            let musicWidthScale = CGFloat(musicWidth / defaultMusicWidth)
            let timerWidthScale = CGFloat(timerWidth / LockScreenTimerWidget.defaultWidth)
            let timerSize = CGSize(
                width: (screenRect.width * 0.5) * timerWidthScale,
                height: screenRect.height * 0.2
            )
            let musicSize = CGSize(
                width: (screenRect.width * 0.56) * musicWidthScale,
                height: screenRect.height * 0.34
            )

            ZStack {
                RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    .frame(width: screenRect.width, height: screenRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 18)
                    .position(x: screenRect.midX, y: screenRect.midY)

                weatherPanel(size: weatherSize)
                    .position(x: centerX, y: weatherBaseY - CGFloat(weatherOffset))
                    .gesture(weatherDragGesture(in: screenRect, baseY: weatherBaseY, panelSize: weatherSize))

                timerPanel(size: timerSize)
                    .position(x: centerX, y: timerBaseY - CGFloat(timerOffset))
                    .gesture(timerDragGesture(in: screenRect, baseY: timerBaseY, panelSize: timerSize))

                musicPanel(size: musicSize)
                    .position(x: centerX, y: musicBaseY - CGFloat(musicOffset))
                    .gesture(musicDragGesture(in: screenRect, baseY: musicBaseY, panelSize: musicSize))
            }
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: weatherOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicWidth)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerWidth)
    }

    private func weatherPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.78), Color.blue.opacity(0.52)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Weather", systemImage: "cloud.sun.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Inline snapshot preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 16)
            }
            .shadow(color: Color.blue.opacity(0.22), radius: 10, x: 0, y: 8)
    }

    private func musicPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.68), Color.pink.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Media", systemImage: "play.square.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Lock screen panel preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 18)
            }
            .shadow(color: Color.purple.opacity(0.24), radius: 12, x: 0, y: 9)
    }

    private func timerPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.orange.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay {
                VStack(spacing: 6) {
                    Text("Timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("00:05:00")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 8)
    }

    private func weatherDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isWeatherDragging {
                    isWeatherDragging = true
                    weatherStartOffset = weatherOffset
                }

                let proposed = weatherStartOffset - Double(value.translation.height)
                weatherOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isWeatherDragging = false
            }
    }

    private func musicDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isMusicDragging {
                    isMusicDragging = true
                    musicStartOffset = musicOffset
                }

                let proposed = musicStartOffset - Double(value.translation.height)
                musicOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isMusicDragging = false
            }
    }

    private func timerDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTimerDragging {
                    isTimerDragging = true
                    timerStartOffset = timerOffset
                }

                let proposed = timerStartOffset - Double(value.translation.height)
                timerOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isTimerDragging = false
            }
    }

    private func clampedOffset(
        _ proposed: Double,
        baseCenterY: CGFloat,
        panelHeight: CGFloat,
        screenRect: CGRect
    ) -> Double {
        let halfHeight = panelHeight / 2
        let minCenterY = screenRect.minY + halfHeight
        let maxCenterY = screenRect.maxY - halfHeight
        let proposedCenter = baseCenterY - CGFloat(proposed)
        let clampedCenter = min(max(proposedCenter, minCenterY), maxCenterY)
        let derivedOffset = Double(baseCenterY - clampedCenter)
        return min(max(derivedOffset, offsetRange.lowerBound), offsetRange.upperBound)
    }
}

private func copyLatestCrashReport() {
    let crashReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
    let fileManager = FileManager.default

    do {
        let files = try fileManager.contentsOfDirectory(atPath: crashReportsPath)
        let crashFiles = files.filter { $0.contains("DynamicIsland") && $0.hasSuffix(".crash") }

        guard let latestCrash = crashFiles.sorted(by: >).first else {
            let alert = NSAlert()
            alert.messageText = "No Crash Reports Found"
            alert.informativeText = "No crash reports found for DynamicIsland"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let crashPath = (crashReportsPath as NSString).appendingPathComponent(latestCrash)
        let crashContent = try String(contentsOfFile: crashPath, encoding: .utf8)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(crashContent, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Crash Report Copied"
        alert.informativeText = "Crash report '\(latestCrash)' has been copied to clipboard"
        alert.alertStyle = .informational
        alert.runModal()
    } catch {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = "Failed to read crash reports: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}

struct Shortcuts: View {
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature

    private func highlightID(_ title: String) -> String {
        SettingsTab.shortcuts.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShortcuts) {
                    Text("Enable global keyboard shortcuts")
                }
                .settingsHighlight(id: highlightID("Enable global keyboard shortcuts"))
            } header: {
                Text("General")
            } footer: {
                Text("When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if enableShortcuts {
                Section {
                    KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Media")
                } footer: {
                    Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Toggle the Dynamic Island open or closed from anywhere.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Start Demo Timer:", name: .startDemoTimer)
                                .disabled(!enableShortcuts || !enableTimerFeature)
                            if !enableTimerFeature {
                                Text("Timer feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Timer")
                } footer: {
                    Text("Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Clipboard History:", name: .clipboardHistoryPanel)
                                .disabled(!enableShortcuts || !enableClipboardManager)
                            if !enableClipboardManager {
                                Text("Clipboard feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Clipboard")
                } footer: {
                    Text("Opens the clipboard history panel. Default is Cmd+Shift+V (similar to Windows+V on PC). Only works when clipboard feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Screen Assistant:", name: .screenAssistantPanel)
                                .disabled(!enableShortcuts || !Defaults[.enableScreenAssistant])
                            if !Defaults[.enableScreenAssistant] {
                                Text("Screen Assistant feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("AI Assistant")
                } footer: {
                    Text("Opens the AI assistant panel for file analysis and conversation. Default is Cmd+Shift+A. Only works when screen assistant feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Toggle Terminal Tab:", name: .toggleTerminalTab)
                                .disabled(!enableShortcuts || !Defaults[.enableTerminalFeature])
                            if !Defaults[.enableTerminalFeature] {
                                Text("Terminal feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Opens the terminal tab in the notch. Default is Ctrl+`. Only works when terminal feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Color Picker Panel:", name: .colorPickerPanel)
                                .disabled(!enableShortcuts || !enableColorPickerFeature)
                            if !enableColorPickerFeature {
                                Text("Color Picker feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Color Picker")
                } footer: {
                    Text("Opens the color picker panel for screen color capture. Default is Cmd+Shift+P. Only works when color picker feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard shortcuts are disabled")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Enable global keyboard shortcuts above to customize your shortcuts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(LocalizedStringKey(text))
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(SettingsPalette.warn)
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SettingsPalette.warn)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct TimerSettings: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerPresets) private var timerPresets
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    @Default(.mirrorSystemTimer) private var mirrorSystemTimer
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    @State private var showingResetConfirmation = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.timer.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var timerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        Form {
            if !enableTimerFeature {
                Section {
                    Text("Off: no timers, no Pomodoro, nothing in the notch.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                timerFeatureSection
                pomodoroFocusSection
                timerConfigurationSections
            }
        }
        .navigationTitle("Timers")
        .onAppear { syncCustomDuration() }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(newValue) }
    }

    @Default(.pomodoroHoldsInterruptions) private var pomodoroHoldsInterruptions
    @Default(.pomodoroControlsFocus) private var pomodoroControlsFocus
    @Default(.pomodoroFocusOnShortcut) private var pomodoroFocusOnShortcut
    @Default(.pomodoroFocusOffShortcut) private var pomodoroFocusOffShortcut

    @ViewBuilder
    private var pomodoroFocusSection: some View {
        Section {
            SettingsToggle(key: .pomodoroHoldsInterruptions, title: "Don't disturb me during focus",
                           detail: "Messages, calls and finished agents wait until the break. Approvals still show, quietly.",
                           highlightID: highlightID("Don't disturb me during focus"))
            if pomodoroHoldsInterruptions {
                SettingsToggle(key: .pomodoroAllowsCalls, title: "Let calls through",
                               highlightID: highlightID("Let calls through"))
                    .padding(.leading, 16)
            }
            SettingsToggle(key: .pomodoroControlsFocus, title: "Also silence macOS",
                           detail: "Turns on a Focus, so other apps' banners stay quiet too.",
                           highlightID: highlightID("Also silence macOS (Focus)"))
            if pomodoroControlsFocus {
                Group {
                    TextField("Shortcut that turns Focus on", text: $pomodoroFocusOnShortcut)
                    TextField("Shortcut that turns Focus off", text: $pomodoroFocusOffShortcut)
                    HStack {
                        SettingsRowLabel(title: "Make the two shortcuts",
                                         detail: "In Shortcuts, use Set Focus, then type their names above.")
                        Spacer()
                        Button("Open Shortcuts") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        }
                    }
                }
                .padding(.leading, 16)
            }
        } header: {
            Text("Pomodoro")
        }
    }

    @ViewBuilder
    private var timerFeatureSection: some View {
        Section {
            Toggle(isOn: $coordinator.timerLiveActivityEnabled.animation()) {
                SettingsRowLabel(title: "Show timers in the closed notch",
                                 detail: "The time left, without opening the notch.")
            }
            .settingsHighlight(id: highlightID("Show timers in the closed notch"))
            SettingsToggle(key: .mirrorSystemTimer, title: "Follow Clock app timers",
                           detail: "Timers you start in the Clock app show here too. Needs Accessibility.",
                           highlightID: highlightID("Mirror macOS Clock timers"))
            Picker("Controls appear as", selection: $timerDisplayMode) {
                ForEach(TimerDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help(timerDisplayMode.description)
            .settingsHighlight(id: highlightID("Timer controls appear as"))
        } header: {
            Text("Timers")
        }
    }

    @ViewBuilder
    private var timerConfigurationSections: some View {
        Group {
            appearanceSection
            timerPresetsSection
            customTimerSection
            timerSoundSection
        }
        .onAppear {
            if showsLabel {
                controlWindowEnabled = false
            }
        }
        .onChange(of: showsLabel) { _, show in
            if show {
                controlWindowEnabled = false
            }
        }
    }

    @ViewBuilder
    private var customTimerSection: some View {
        Section {
            TimerDurationStepperRow(title: String(localized: "Hours"), value: $customHours, range: 0...23)
            TimerDurationStepperRow(title: String(localized: "Minutes"), value: $customMinutes, range: 0...59)
            TimerDurationStepperRow(title: String(localized: "Seconds"), value: $customSeconds, range: 0...59)
            LabeledContent("Custom is") {
                Text(customDurationDisplay).monospacedDigit().foregroundStyle(.secondary)
            }
        } header: {
            Text("Custom timer")
        } footer: {
            Text("How long the Custom choice in the timer menu runs.")
        }
        .onChange(of: customHours) { _, _ in updateCustomDuration() }
        .onChange(of: customMinutes) { _, _ in updateCustomDuration() }
        .onChange(of: customSeconds) { _, _ in updateCustomDuration() }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Colour", selection: $colorMode) {
                ForEach(TimerIconColorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .settingsHighlight(id: highlightID("Timer tint"))

            if colorMode == .solid {
                ColorPicker("Pick a colour", selection: $solidColor, supportsOpacity: false)
                    .padding(.leading, 16)
                    .settingsHighlight(id: highlightID("Solid colour"))
            }

            Toggle("Show the timer's name", isOn: $showsLabel)
            Toggle("Show the time left", isOn: $showsCountdown)
            Toggle("Show progress", isOn: $showsProgress)
            if showsProgress {
                Picker("Progress as", selection: $progressStyle) {
                    ForEach(TimerProgressStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.leading, 16)
                .settingsHighlight(id: highlightID("Progress style"))
            }
            Toggle(isOn: $controlWindowEnabled) {
                SettingsRowLabel(title: "Floating pause and stop",
                                 detail: showsLabel ? "Hide the timer's name to use these." : "Buttons beside the notch while a timer runs.")
            }
            .disabled(showsLabel)
        } header: {
            Text("In the closed notch")
        }
    }

    @ViewBuilder
    private var timerPresetsSection: some View {
        Section {
            if timerPresets.isEmpty {
                Text("No presets yet. Add one to see it in the timer menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                TimerPresetListView(
                    presets: $timerPresets,
                    highlightProvider: highlightID,
                    moveUp: movePresetUp,
                    moveDown: movePresetDown,
                    remove: removePreset
                )
            }

            HStack {
                Button(action: addPreset) {
                    Label("Add Preset", systemImage: "plus")
                }
                .settingsPrimaryButton()

                Spacer()

                Button("Restore Defaults…") { showingResetConfirmation = true }
                    .settingsDestructiveButton()
                    .confirmationDialog("Restore the default presets?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                        Button("Restore", role: .destructive, action: resetPresets)
                    } message: {
                        Text("Your own presets are removed.")
                    }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("They show in the timer menu in this order.")
        }
    }

    @ViewBuilder
    private var timerSoundSection: some View {
        Section {
            HStack {
                if let customTimerSoundPath = UserDefaults.standard.string(forKey: "customTimerSoundPath") {
                    SettingsRowLabel(title: "Sound", detail: URL(fileURLWithPath: customTimerSoundPath).lastPathComponent)
                } else {
                    SettingsRowLabel(title: "Sound", detail: "The NotchFlow sound")
                }
                Spacer()
                if UserDefaults.standard.string(forKey: "customTimerSoundPath") != nil {
                    Button("Use Default") {
                        UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                    }
                }
                Button("Choose…", action: selectCustomTimerSound)
            }
        } header: {
            Text("When a timer ends")
        } footer: {
            Text("MP3, M4A, WAV or AIFF.")
        }
    }

    private var customDurationDisplay: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = customTimerDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: customTimerDuration) ?? "0:00"
    }

    private func syncCustomDuration(_ value: Double? = nil) {
        let baseValue = value ?? customTimerDuration
        let components = TimerPreset.components(for: baseValue)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateCustomDuration() {
        let duration = TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
        customTimerDuration = duration
    }

    private func addPreset() {
        let nextIndex = timerPresets.count + 1
        let defaultColor = Defaults[.accentColor]
        let newPreset = TimerPreset(name: "Preset \(nextIndex)", duration: 5 * 60, color: defaultColor)
        _ = withAnimation(.smooth) {
            timerPresets.append(newPreset)
        }
    }

    private func movePresetUp(_ index: Int) {
        guard index > timerPresets.startIndex else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index - 1)
        }
    }

    private func movePresetDown(_ index: Int) {
        guard index < timerPresets.index(before: timerPresets.endIndex) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index + 1)
        }
    }

    private func removePreset(_ index: Int) {
        guard timerPresets.indices.contains(index) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.remove(at: index)
        }
    }

    private func resetPresets() {
        _ = withAnimation(.smooth) {
            timerPresets = TimerPreset.defaultPresets
        }
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            if let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            }
        }
    }
}

private struct TimerDurationStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
    }
}

private struct TimerPresetListView: View {
    @Binding var presets: [TimerPreset]
    let highlightProvider: (String) -> String
    let moveUp: (Int) -> Void
    let moveDown: (Int) -> Void
    let remove: (Int) -> Void

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            presetRow(at: index)
        }
    }

    @ViewBuilder
    private func presetRow(at index: Int) -> some View {
        TimerPresetEditorRow(
            preset: $presets[index],
            isFirst: index == presets.startIndex,
            isLast: index == presets.index(before: presets.endIndex),
            highlightID: highlightID(for: index),
            moveUp: { moveUp(index) },
            moveDown: { moveDown(index) },
            remove: { remove(index) }
        )
    }

    private func highlightID(for index: Int) -> String? {
        index == presets.startIndex ? highlightProvider("Accent colour") : nil
    }
}

private struct TimerPresetEditorRow: View {
    @Binding var preset: TimerPreset
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let highlightID: String?

    init(
        preset: Binding<TimerPreset>,
        isFirst: Bool,
        isLast: Bool,
        highlightID: String? = nil,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        _preset = preset
        self.isFirst = isFirst
        self.isLast = isLast
        self.highlightID = highlightID
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.remove = remove
    }

    private var components: TimerPreset.DurationComponents {
        TimerPreset.components(for: preset.duration)
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { components.hours },
            set: { updateDuration(hours: $0) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { components.minutes },
            set: { updateDuration(minutes: $0) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { components.seconds },
            set: { updateDuration(seconds: $0) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { preset.color },
            set: { preset.updateColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                TextField("Preset name", text: $preset.name)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text(preset.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                TimerPresetComponentControl(title: String(localized: "Hours"), value: hoursBinding, range: 0...23)
                TimerPresetComponentControl(title: String(localized: "Minutes"), value: minutesBinding, range: 0...59)
                TimerPresetComponentControl(title: String(localized: "Seconds"), value: secondsBinding, range: 0...59)
            }

            ColorPicker("Accent colour", selection: colorBinding, supportsOpacity: false)
                .frame(maxWidth: 240, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: moveUp) {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .disabled(isFirst)

                Button(action: moveDown) {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .disabled(isLast)

                Spacer()

                Button(role: .destructive, action: remove) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 6)
        .settingsHighlightIfPresent(highlightID)
    }

    private func updateDuration(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        var values = components
        if let hours { values.hours = hours }
        if let minutes { values.minutes = minutes }
        if let seconds { values.seconds = seconds }
        preset.duration = TimerPreset.duration(from: values)
    }
}

private struct TimerPresetComponentControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
        }
        .frame(width: 110, alignment: .leading)
    }
}

struct StatsSettings: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableLLMUsageFeature) var enableLLMUsageFeature
    @Default(.statsStopWhenNotchCloses) var statsStopWhenNotchCloses
    @Default(.statsUpdateInterval) var statsUpdateInterval
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @Default(.cpuTemperatureUnit) var cpuTemperatureUnit

    private func highlightID(_ title: String) -> String {
        SettingsTab.stats.highlightID(for: title)
    }

    var enabledGraphsCount: Int {
        [showCpuGraph, showMemoryGraph, showGpuGraph, showNetworkGraph, showDiskGraph].filter { $0 }.count
    }

    private var formattedUpdateInterval: String {
        let seconds = Int(statsUpdateInterval.rounded())
        if seconds >= 60 {
            return "60 s (1 min)"
        } else if seconds == 1 {
            return "1 s"
        } else {
            return "\(seconds) s"
        }
    }

    private var shouldShowStatsBatteryWarning: Bool {
        !statsStopWhenNotchCloses && statsUpdateInterval <= 5
    }

    var body: some View {
        Form {
            if !enableStatsFeature {
                Section {
                    Text("Off: no Stats tab, and nothing is measured.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    SettingsToggle(key: .showCpuGraph, title: "CPU", highlightID: highlightID("CPU"))
                    if showCpuGraph {
                        Picker("Temperature in", selection: $cpuTemperatureUnit) {
                            ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                                Text(unit.localizedName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.leading, 16)
                        .settingsHighlight(id: highlightID("Temperature unit"))
                    }
                    SettingsToggle(key: .showMemoryGraph, title: "Memory", highlightID: highlightID("Memory"))
                    SettingsToggle(key: .showGpuGraph, title: "GPU", highlightID: highlightID("GPU"))
                    SettingsToggle(key: .showNetworkGraph, title: "Network", detail: "Download and upload speed.",
                                   highlightID: highlightID("Network"))
                    SettingsToggle(key: .showDiskGraph, title: "Disk", detail: "Read and write speed.",
                                   highlightID: highlightID("Disk"))
                } header: {
                    Text("Graphs")
                } footer: {
                    if enabledGraphsCount >= 4 {
                        Text("With \(enabledGraphsCount) graphs the notch gets wider to fit them in one row.")
                    }
                }

                Section {
                    SettingsToggle(key: .statsStopWhenNotchCloses, title: "Stop when the notch closes",
                                   detail: "Saves battery. Measuring starts again when you open the Stats tab.",
                                   highlightID: highlightID("Stop when the notch closes"))
                    LabeledContent {
                        HStack {
                            Slider(value: $statsUpdateInterval, in: 1...60, step: 1)
                                .frame(maxWidth: 180)
                                .accessibilityLabel("How often")
                            Text(formattedUpdateInterval).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    } label: {
                        SettingsRowLabel(title: "How often", detail: "How often the numbers refresh.")
                    }
                    if shouldShowStatsBatteryWarning {
                        SettingsStatus(text: "Refreshing this often all the time uses more battery.", kind: .warn)
                    }
                } header: {
                    Text("Measuring")
                }

                Section {
                    LabeledContent("Measuring") {
                        HStack(spacing: 10) {
                            SettingsStatus(text: statsManager.isMonitoring ? "On" : "Stopped",
                                           kind: statsManager.isMonitoring ? .ok : .neutral)
                            Button(statsManager.isMonitoring ? "Stop" : "Start") {
                                if statsManager.isMonitoring {
                                    statsManager.stopMonitoring()
                                } else {
                                    statsManager.startMonitoring()
                                }
                            }
                        }
                    }
                    if statsManager.isMonitoring {
                        if showCpuGraph { LabeledContent("CPU", value: statsManager.cpuUsageString) }
                        if showMemoryGraph { LabeledContent("Memory", value: statsManager.memoryUsageString) }
                        if showGpuGraph { LabeledContent("GPU", value: statsManager.gpuUsageString) }
                        if showNetworkGraph {
                            LabeledContent("Network", value: String(format: "↓ %.1f MB/s  ↑ %.1f MB/s", statsManager.networkDownload, statsManager.networkUpload))
                        }
                        if showDiskGraph {
                            LabeledContent("Disk", value: String(format: "Read %.1f MB/s  Write %.1f MB/s", statsManager.diskRead, statsManager.diskWrite))
                        }
                        LabeledContent("Updated") {
                            Text(statsManager.lastUpdated, style: .relative).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Right now")
                }

                Section {
                    HStack {
                        SettingsRowLabel(title: "Clear the history", detail: "Empties the graphs. Stop measuring first.")
                        Spacer()
                        Button("Clear") { statsManager.clearHistory() }
                            .settingsDestructiveButton()
                            .disabled(statsManager.isMonitoring)
                    }
                } header: {
                    Text("Data")
                }
            }

            Section {
                SettingsToggle(key: .enableLLMUsageFeature, title: "AI usage tab",
                               detail: "A Usage tab with your tokens and spend for AI tools.",
                               highlightID: highlightID("AI usage tab"))
                if enableLLMUsageFeature {
                    SettingsToggle(key: .enableClaudeProvider, title: "Claude", highlightID: highlightID("Claude Provider"))
                        .padding(.leading, 16)
                    SettingsToggle(key: .enableCodexProvider, title: "Codex", highlightID: highlightID("Codex Provider"))
                        .padding(.leading, 16)
                    SettingsToggle(key: .enableCursorProvider, title: "Cursor", highlightID: highlightID("Cursor Provider"))
                        .padding(.leading, 16)
                }
            } header: {
                Text("AI usage")
            }
        }
        .navigationTitle("Stats")
        .onChange(of: enableStatsFeature) { _, newValue in
            if !newValue {
                statsManager.stopMonitoring()
            }
        }
    }
}

struct ClipboardSettings: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardDisplayMode) var clipboardDisplayMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.clipboard.highlightID(for: title)
    }

    @State private var confirmClearHistory = false
    @State private var confirmClearPinned = false

    var body: some View {
        Form {
            if !enableClipboardManager {
                Section {
                    Text("Off: nothing you copy is kept.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Picker("Show it as", selection: $clipboardDisplayMode) {
                        ForEach(ClipboardDisplayMode.allCases.filter { $0 != .popover }, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .settingsHighlight(id: highlightID("Show it as"))
                    LabeledContent("Keeps") {
                        Text("The last 20 copies").foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("History Size"))
                    LabeledContent("Right now") {
                        SettingsStatus(text: clipboardManager.isMonitoring
                                       ? "\(clipboardManager.clipboardHistory.count) copies, \(clipboardManager.pinnedItems.count) pinned"
                                       : "Stopped",
                                       kind: clipboardManager.isMonitoring ? .ok : .warn)
                    }
                } header: {
                    Text("Clipboard")
                } footer: {
                    switch clipboardDisplayMode {
                    case .panel:
                        Text("A floating window by the notch. Open it with ⌘⇧V.")
                    case .separateTab, .popover:
                        Text("Its own tab in the notch, next to Notes if that's on. Open it with ⌘⇧V.")
                    }
                }

                Section {
                    HStack {
                        SettingsRowLabel(title: "Clear the history", detail: "Your pinned copies stay.")
                        Spacer()
                        Button("Clear…") { confirmClearHistory = true }
                            .settingsDestructiveButton()
                            .disabled(clipboardManager.clipboardHistory.isEmpty)
                    }
                    HStack {
                        SettingsRowLabel(title: "Clear pinned copies")
                        Spacer()
                        Button("Clear…") { confirmClearPinned = true }
                            .settingsDestructiveButton()
                            .disabled(clipboardManager.pinnedItems.isEmpty)
                    }
                } header: {
                    Text("Data")
                }
            }
        }
        .navigationTitle("Clipboard")
        .confirmationDialog("Clear the clipboard history?", isPresented: $confirmClearHistory) {
            Button("Clear History", role: .destructive) { clipboardManager.clearHistory() }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Clear your pinned copies?", isPresented: $confirmClearPinned) {
            Button("Clear Pinned", role: .destructive) {
                clipboardManager.pinnedItems.removeAll()
                clipboardManager.savePinnedItemsToDefaults()
            }
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: enableClipboardManager) { _, enabled in
            if enabled {
                clipboardManager.startMonitoring()
            } else {
                clipboardManager.stopMonitoring()
            }
        }
        .onAppear {
            if enableClipboardManager && !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct ScreenAssistantSettings: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @Default(.enableScreenAssistant) var enableScreenAssistant
    @Default(.screenAssistantDisplayMode) var screenAssistantDisplayMode
    @Default(.geminiApiKey) var geminiApiKey
    @State private var apiKeyText = ""
    @State private var showingApiKey = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.screenAssistant.highlightID(for: title)
    }

    @State private var confirmClearFiles = false

    var body: some View {
        Form {
            if !enableScreenAssistant {
                Section {
                    Text("Off: no AI button, and nothing is sent anywhere.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Picker("Show it as", selection: $screenAssistantDisplayMode) {
                        ForEach(ScreenAssistantDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .settingsHighlight(id: highlightID("Show it as"))
                    LabeledContent("Right now") {
                        SettingsStatus(text: screenAssistantManager.isRecording
                                       ? "Recording"
                                       : "Ready · \(screenAssistantManager.attachedFiles.count) files attached",
                                       kind: screenAssistantManager.isRecording ? .warn : .neutral)
                    }
                } header: {
                    Text("Assistant")
                } footer: {
                    switch screenAssistantDisplayMode {
                    case .popover:
                        Text("Drops down from the AI button. Open it with ⌘⇧A.")
                    case .panel:
                        Text("A floating window by the notch. Open it with ⌘⇧A.")
                    }
                }

                Section {
                    HStack {
                        SettingsRowLabel(title: "Gemini API key",
                                         detail: geminiApiKey.isEmpty ? nil : "Saved")
                        Spacer()
                        if geminiApiKey.isEmpty {
                            SettingsStatus(text: "Not set", kind: .warn)
                        }
                        Button(showingApiKey ? "Cancel" : (geminiApiKey.isEmpty ? "Add…" : "Change…")) {
                            showingApiKey.toggle()
                            apiKeyText = ""
                        }
                    }
                    if showingApiKey {
                        HStack {
                            SecureField("Paste your Gemini API key", text: $apiKeyText)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                Defaults[.geminiApiKey] = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
                                showingApiKey = false
                                apiKeyText = ""
                            }
                            .settingsPrimaryButton()
                            .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Link("Get a free key from Google AI Studio", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                            .font(.callout)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("What you ask, with any files you attach, goes to Google's Gemini.")
                }

                Section {
                    HStack {
                        SettingsRowLabel(title: "Remove attached files", detail: "Files and voice recordings you gave the assistant.")
                        Spacer()
                        Button("Remove…") { confirmClearFiles = true }
                            .settingsDestructiveButton()
                            .disabled(screenAssistantManager.attachedFiles.isEmpty)
                    }
                } header: {
                    Text("Data")
                }
            }
        }
        .navigationTitle("Screen Assistant")
        .confirmationDialog("Remove all attached files?", isPresented: $confirmClearFiles) {
            Button("Remove Files", role: .destructive) { screenAssistantManager.clearAllFiles() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct ColorPickerSettings: View {
    @ObservedObject var colorPickerManager = ColorPickerManager.shared
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.showColorFormats) var showColorFormats
    @Default(.colorPickerDisplayMode) var colorPickerDisplayMode
    @Default(.showColorPickerIcon) var showColorPickerIcon

    private func highlightID(_ title: String) -> String {
        SettingsTab.colorPicker.highlightID(for: title)
    }

    @State private var confirmClearColors = false

    var body: some View {
        Form {
            if !enableColorPickerFeature {
                Section {
                    Text("Off: no colour picker in the notch.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    SettingsToggle(key: .showColorPickerIcon, title: "Button in the notch",
                                   detail: "An eyedropper button next to the tabs.",
                                   highlightID: highlightID("Button in the notch"))
                    Picker("Show it as", selection: $colorPickerDisplayMode) {
                        ForEach(ColorPickerDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .settingsHighlight(id: highlightID("Show it as"))
                    SettingsToggle(key: .showColorFormats, title: "Every colour format",
                                   detail: "HEX, RGB, HSL and more, not only HEX.",
                                   highlightID: highlightID("Every colour format"))
                } header: {
                    Text("Colour picker")
                } footer: {
                    Text("Open it with ⌘⇧P.")
                }

                Section {
                    HStack {
                        SettingsRowLabel(title: "Pick a colour now",
                                         detail: colorPickerManager.isPickingColor ? "Picking…" : "\(colorPickerManager.colorHistory.count) colours picked so far")
                        Spacer()
                        Button("Show Panel") { ColorPickerPanelManager.shared.showColorPickerPanel() }
                        Button("Pick") { colorPickerManager.startColorPicking() }
                            .settingsPrimaryButton()
                            .disabled(colorPickerManager.isPickingColor)
                    }
                } header: {
                    Text("Try it")
                }

                Section {
                    HStack {
                        SettingsRowLabel(title: "Clear picked colours")
                        Spacer()
                        Button("Clear…") { confirmClearColors = true }
                            .settingsDestructiveButton()
                            .disabled(colorPickerManager.colorHistory.isEmpty)
                    }
                } header: {
                    Text("Data")
                }
            }
        }
        .navigationTitle("Color Picker")
        .confirmationDialog("Clear every picked colour?", isPresented: $confirmClearColors) {
            Button("Clear Colours", role: .destructive) { colorPickerManager.clearHistory() }
        } message: {
            Text("This can't be undone.")
        }
    }
}

struct CustomOSDSettings: View {
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableOSDVolume) var enableOSDVolume
    @Default(.enableOSDBrightness) var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) var enableOSDKeyboardBacklight
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    @State private var showAlphaWarning = false
    @State private var previewValue: CGFloat = 0.65
    @State private var previewType: SneakContentType = .volume

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var availableOSDMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var osdLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(osdLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                osdLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        Form {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission is needed to intercept system controls for the Custom OSD.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }

            if hasAccessibilityPermission || enableThirdPartyDDCIntegration {
                Section {
                    Toggle("Volume OSD", isOn: $enableOSDVolume)
                        .settingsHighlight(id: highlightID("Volume OSD"))
                    Toggle("Brightness OSD", isOn: $enableOSDBrightness)
                        .settingsHighlight(id: highlightID("Brightness OSD"))
                    Toggle("Keyboard Backlight OSD", isOn: $enableOSDKeyboardBacklight)
                        .settingsHighlight(id: highlightID("Keyboard Backlight OSD"))
                        .disabled(enableThirdPartyDDCIntegration)
                        .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active \u{2014} brightness keys are handled by the external app." : "")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display custom OSD windows.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    Picker("Material", selection: $osdMaterial) {
                        ForEach(availableOSDMaterials, id: \.self) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .settingsHighlight(id: highlightID("Material"))
                    .onChange(of: osdMaterial) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }

                    if osdMaterial == .liquid {
                        if #available(macOS 26.0, *) {
                            Picker("Glass mode", selection: $osdLiquidGlassCustomizationMode) {
                                ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if osdLiquidGlassCustomizationMode == .customLiquid {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Custom liquid variant")
                                        Spacer()
                                        Text("v\(osdLiquidGlassVariant.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: osdLiquidVariantBinding, in: liquidVariantRange, step: 1)
                                }
                            }
                        } else {
                            Text("Custom Liquid is available on macOS 26 or later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Icon & Progress Color", selection: $osdIconColorStyle) {
                        ForEach(OSDIconColorStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Icon & Progress Color"))
                    .onChange(of: osdIconColorStyle) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Material Options:")
                        Text("• Frosted Glass: Translucent blur effect")
                        Text("• Liquid Glass: Modern glass effect (macOS 26+)")
                        Text("• Solid Dark/Light/Auto: Opaque backgrounds")
                        Text("")
                        Text("Color options control the icon and progress bar appearance. Auto adapts to system theme.")
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Text("Live Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            CustomOSDView(
                                type: .constant(previewType),
                                value: .constant(previewValue),
                                icon: .constant("")
                            )
                            .frame(width: 200, height: 200)

                            HStack(spacing: 8) {
                                Button("Volume") {
                                    previewType = .volume
                                }
                                .buttonStyle(.bordered)

                                Button("Brightness") {
                                    previewType = .brightness
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Backlight") {
                                    previewType = .backlight
                                }
                                .buttonStyle(.bordered)
                            }
                            .controlSize(.small)
                            
                            Slider(value: $previewValue, in: 0...1)
                                .frame(width: 160)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Adjust settings above to see changes in real-time. The actual OSD appears at the bottom center of your screen.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Custom OSD")
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), osdMaterial == .liquid {
                osdMaterial = .frosted
                osdLiquidGlassCustomizationMode = .standard
            }
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableCustomOSD = false
            }
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "Accessibility permission required",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "Request Access",
        openSettingsButtonTitle: String = "Open Settings",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(LocalizedStringKey(message))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(LocalizedStringKey(requestButtonTitle)) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(LocalizedStringKey(openSettingsButtonTitle)) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HUD()
}

struct NotesSettingsView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var appleNotesSync = AppleNotesSyncManager.shared
    @Default(.enableNotes) private var enableNotes
    @Default(.enableAppleNotesSync) private var enableAppleNotesSync
    @Default(.appleNotesLastSyncDate) private var appleNotesLastSyncDate

    private func highlightID(_ title: String) -> String {
        SettingsTab.notes.highlightID(for: title)
    }

    var body: some View {
        Form {
            if !enableNotes {
                Section {
                    Text("Off: no Notes tab.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    SettingsToggle(key: .enableNotePinning, title: "Pin notes", detail: "Keep the ones you need at the top.")
                    SettingsToggle(key: .enableNoteSearch, title: "Search")
                    SettingsToggle(key: .enableNoteColorFiltering, title: "Colours", detail: "Colour notes and show only one colour.")
                    SettingsToggle(key: .enableCreateFromClipboard, title: "New note from what you copied")
                    SettingsToggle(key: .enableNoteCharCount, title: "Character count")
                } header: {
                    Text("Notes")
                }

                Section {
                    SettingsToggle(key: .enableAppleNotesSync, title: "Sync with Apple Notes",
                                   detail: "Both ways. NotchFlow's notes go in a NotchFlow folder in Notes.",
                                   highlightID: highlightID("Sync with Apple Notes"))
                    if enableAppleNotesSync {
                        HStack {
                            if let error = appleNotesSync.lastError {
                                SettingsStatus(text: error, kind: .error)
                            } else if let lastSync = appleNotesLastSyncDate {
                                SettingsStatus(text: "Synced \(lastSync.formatted(.relative(presentation: .named)))", kind: .ok)
                            } else {
                                SettingsStatus(text: "Not synced yet")
                            }
                            Spacer()
                            if appleNotesSync.isSyncing {
                                ProgressView().controlSize(.small)
                            }
                            Button("Sync Now") {
                                Task {
                                    let notes = Defaults[.savedNotes]
                                    if let merged = await appleNotesSync.sync(localNotes: notes) {
                                        Defaults[.savedNotes] = merged
                                    }
                                }
                            }
                            .settingsPrimaryButton()
                            .disabled(appleNotesSync.isSyncing)
                        }
                        .padding(.leading, 16)
                        .settingsHighlight(id: highlightID("Sync Now"))
                    }
                } header: {
                    Text("Apple Notes")
                } footer: {
                    Text("macOS asks once to let NotchFlow use Notes.")
                }
            }
        }
        .navigationTitle("Notes")
    }
}

// MARK: - Terminal Settings

struct TerminalSettings: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @Default(.terminalShellPath) var terminalShellPath
    @Default(.terminalFontFamily) var terminalFontFamily
    @Default(.terminalFontSize) var terminalFontSize
    @Default(.terminalOpacity) var terminalOpacity
    @Default(.terminalMaxHeightFraction) var terminalMaxHeightFraction
    @Default(.terminalCursorStyle) var terminalCursorStyle
    @Default(.terminalScrollbackLines) var terminalScrollbackLines
    @Default(.terminalOptionAsMeta) var terminalOptionAsMeta
    @Default(.terminalMouseReporting) var terminalMouseReporting
    @Default(.terminalBoldAsBright) var terminalBoldAsBright
    @Default(.terminalBackgroundColor) var terminalBackgroundColor
    @Default(.terminalForegroundColor) var terminalForegroundColor
    @Default(.terminalCursorColor) var terminalCursorColor
    @Default(.terminalNotifyWhenDone) var terminalNotifyWhenDone
    @Default(.terminalNotifyAfterSeconds) var terminalNotifyAfterSeconds
    @Default(.terminalExternalApp) var terminalExternalApp
    @State private var confirmRestartShell = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.terminal.highlightID(for: title)
    }

    /// Terminal apps installed on this Mac.
    private var installedTerminalApps: [(name: String, bundleID: String)] {
        TerminalCommandPolicy.externalApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    private var formattedMaxHeight: String {
        "\(Int(terminalMaxHeightFraction * 100))% of screen"
    }

    /// All monospaced font families available on the system.
    private var monospacedFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
                || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        .sorted()
    }

    /// Display name for the font picker — shows "System Monospaced" when no custom font is set.
    private var fontDisplayName: String {
        terminalFontFamily.isEmpty ? "System Monospaced" : terminalFontFamily
    }

    private var cursorStyleBinding: Binding<TerminalCursorStyleOption> {
        Binding(
            get: { TerminalCursorStyleOption(rawValue: terminalCursorStyle) ?? .blinkBlock },
            set: { terminalCursorStyle = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            if !enableTerminalFeature {
                Section {
                    Text("Off: no Terminal tab, and no shell running.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    SettingsToggle(key: .terminalStickyMode, title: "Stay open until I click outside",
                                   detail: "The notch doesn't close if the pointer slips away.",
                                   highlightID: highlightID("Keep terminal open"))
                    SettingsToggle(key: .terminalNotifyWhenDone, title: "Tell me when a command finishes",
                                   detail: "When you're looking elsewhere. Its tab gets a green dot too.",
                                   highlightID: highlightID("Tell me when a command finishes"))
                    if terminalNotifyWhenDone {
                        LabeledContent {
                            Stepper(value: $terminalNotifyAfterSeconds, in: 0...600, step: 5) {
                                Text(terminalNotifyAfterSeconds == 0 ? "Every command" : "\(terminalNotifyAfterSeconds)s or longer")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        } label: {
                            Text("Only for commands that ran")
                        }
                        .padding(.leading, 16)
                    }
                    Picker("Open folders in", selection: $terminalExternalApp) {
                        ForEach(installedTerminalApps, id: \.bundleID) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                        if !installedTerminalApps.contains(where: { $0.bundleID == terminalExternalApp }) {
                            Text("Terminal").tag(terminalExternalApp)
                        }
                    }
                    .settingsHighlight(id: highlightID("Open in"))
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Click + in the terminal for another tab. Each keeps running while the notch is closed.")
                }

                Section {
                    Picker("Font", selection: $terminalFontFamily) {
                        Text("System Monospaced").tag("")
                        Divider()
                        ForEach(monospacedFontFamilies, id: \.self) { family in
                            Text(family)
                                .font(.custom(family, size: 13))
                                .tag(family)
                        }
                    }
                    .onChange(of: terminalFontFamily) { _, newValue in
                        terminalManager.applyFontFamily(newValue)
                    }
                    .settingsHighlight(id: highlightID("Font family"))

                    SettingsSlider(title: "Font size", value: $terminalFontSize, range: 8...24, step: 1,
                                   valueText: "\(Int(terminalFontSize)) pt")
                        .onChange(of: terminalFontSize) { _, newValue in
                            terminalManager.applyFontSize(newValue)
                        }
                        .settingsHighlight(id: highlightID("Font size"))

                    SettingsSlider(title: "Background opacity", detail: "Text always stays solid.",
                                   value: $terminalOpacity, range: 0.3...1.0, step: 0.05,
                                   valueText: "\(Int(terminalOpacity * 100))%")
                        .onChange(of: terminalOpacity) { _, newValue in
                            terminalManager.applyOpacity(newValue)
                        }
                        .settingsHighlight(id: highlightID("Terminal opacity"))

                    SettingsSlider(title: "Tallest it gets", value: $terminalMaxHeightFraction, range: 0.2...0.5, step: 0.05,
                                   valueText: "\(Int(terminalMaxHeightFraction * 100))%")
                        .settingsHighlight(id: highlightID("Maximum height"))

                    Picker("Cursor", selection: cursorStyleBinding) {
                        ForEach(TerminalCursorStyleOption.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .onChange(of: terminalCursorStyle) { _, newValue in
                        if let style = TerminalCursorStyleOption(rawValue: newValue) {
                            terminalManager.applyCursorStyle(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Cursor style"))
                } header: {
                    Text("Look")
                }

                Section {
                    ColorPicker("Background", selection: $terminalBackgroundColor, supportsOpacity: false)
                        .onChange(of: terminalBackgroundColor) { _, newValue in
                            terminalManager.applyBackgroundColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Background color"))

                    ColorPicker("Text", selection: $terminalForegroundColor, supportsOpacity: false)
                        .onChange(of: terminalForegroundColor) { _, newValue in
                            terminalManager.applyForegroundColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Foreground color"))

                    ColorPicker("Cursor", selection: $terminalCursorColor, supportsOpacity: false)
                        .onChange(of: terminalCursorColor) { _, newValue in
                            terminalManager.applyCursorColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Cursor color"))

                    Toggle(isOn: $terminalBoldAsBright) {
                        SettingsRowLabel(title: "Bold text in bright colours", detail: "Off makes bold text heavier instead.")
                    }
                    .onChange(of: terminalBoldAsBright) { _, newValue in
                        terminalManager.applyBoldAsBright(newValue)
                    }
                    .settingsHighlight(id: highlightID("Bold as bright"))
                } header: {
                    Text("Colours")
                }

                Section {
                    HStack {
                        Text("Shell")
                        Spacer()
                        TextField("", text: $terminalShellPath, prompt: Text("/bin/zsh"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .multilineTextAlignment(.trailing)
                    }
                    .settingsHighlight(id: highlightID("Shell path"))

                    SettingsSlider(title: "Lines to keep", detail: "More lines use more memory.",
                                   value: Binding(
                                       get: { Double(terminalScrollbackLines) },
                                       set: { terminalScrollbackLines = Int($0) }
                                   ),
                                   range: 100...10000, step: 100,
                                   valueText: "\(terminalScrollbackLines)")
                        .onChange(of: terminalScrollbackLines) { _, newValue in
                            terminalManager.applyScrollback(newValue)
                        }
                        .settingsHighlight(id: highlightID("Scrollback lines"))

                    Toggle(isOn: $terminalOptionAsMeta) {
                        SettingsRowLabel(title: "Option key as Meta", detail: "Option+key sends Esc+key, for shells and editors.")
                    }
                    .onChange(of: terminalOptionAsMeta) { _, newValue in
                        terminalManager.applyOptionAsMeta(newValue)
                    }
                    .settingsHighlight(id: highlightID("Option as Meta"))

                    Toggle(isOn: $terminalMouseReporting) {
                        SettingsRowLabel(title: "Mouse in terminal apps", detail: "Clicks and scrolling go to apps like vim or tmux.")
                    }
                    .onChange(of: terminalMouseReporting) { _, newValue in
                        terminalManager.applyMouseReporting(newValue)
                    }
                    .settingsHighlight(id: highlightID("Mouse reporting"))

                    HStack {
                        SettingsRowLabel(title: "Restart the shell", detail: "Whatever is running in it stops.")
                        Spacer()
                        Button("Restart…") { confirmRestartShell = true }
                            .settingsDestructiveButton()
                            .disabled(!terminalManager.isProcessRunning)
                    }
                } header: {
                    Text("Advanced")
                }
            }
        }
        .navigationTitle("Terminal")
        .confirmationDialog("Restart the shell?", isPresented: $confirmRestartShell) {
            Button("Restart Shell", role: .destructive) { terminalManager.restartShell() }
        } message: {
            Text("Anything running in the terminal stops.")
        }
    }
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.
struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // resize to keep memory low.
                let thumb = NSImage(size: NSSize(width: 32, height: 32))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

private struct QuickShareProviderIconImage: View {
    let provider: QuickShareProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                AppIconImage(
                    bundleIdentifiers: provider.bundleIdentifiersFallback,
                    assetFallback: provider.assetFallbackName,
                    symbolFallback: provider.symbolFallbackName,
                    symbolColor: .accentColor,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
    }
}

private extension QuickShareProvider {
    var bundleIdentifiersFallback: [String] {
        switch id {
        case "LocalSend":
            return ["org.localsend.localsend_app", "org.localsend.localsend"]
        case "AirDrop":
            return ["com.apple.finder"]
        case "Mail":
            return ["com.apple.mail"]
        case "Messages":
            return ["com.apple.MobileSMS", "com.apple.iChat"]
        case "Notes":
            return ["com.apple.Notes"]
        case "Reminders":
            return ["com.apple.reminders"]
        case "Add to Safari Reading List":
            return ["com.apple.Safari"]
        default:
            return []
        }
    }

    var assetFallbackName: String? {
        id == "LocalSend" ? "LocalSend" : nil
    }

    var symbolFallbackName: String {
        id == "System Share Menu" ? "square.and.arrow.up.on.square" : "square.and.arrow.up"
    }
}

// MARK: - Page header and app controls

/// Every page's header: icon, title, one sentence, status, and the main switch
/// for features that have one.
private struct SettingsTabHeader: View {
    let tab: SettingsTab

    var body: some View {
        if let key = tab.masterKey {
            SettingsTabSwitchHeader(tab: tab, key: key)
        } else {
            SettingsPageHeader(symbol: tab.systemImage, tint: tab.tint, title: tab.title, detail: tab.summary,
                               statusView: AnyView(SettingsTabStatus(tab: tab)))
        }
    }
}

private struct SettingsTabSwitchHeader: View {
    let tab: SettingsTab
    @Default private var isOn: Bool

    init(tab: SettingsTab, key: Defaults.Key<Bool>) {
        self.tab = tab
        _isOn = Default(key)
    }

    var body: some View {
        SettingsPageHeader(symbol: tab.systemImage, tint: tab.tint, title: tab.title, detail: tab.summary,
                           statusView: AnyView(SettingsTabStatus(tab: tab)), isOn: $isOn)
            .settingsHighlight(id: searchID)
    }

    /// The search tags of the main switches ("orbit-Use Orbit").
    private var searchID: String {
        switch tab {
        case .orbit: return "orbit-Use Orbit"
        case .agents: return "agents-AI Agents"
        case .timer: return "timer-Use Timers"
        case .stats: return "stats-Use Stats"
        case .notes: return "notes-Use Notes"
        case .clipboard: return "clipboard-Use Clipboard"
        case .terminal: return "terminal-Use Terminal"
        case .whatsapp: return "whatsapp-Use WhatsApp"
        case .glance: return "glance-Use Glance"
        case .shelf: return "shelf-Use Shelf"
        case .colorPicker: return "colorPicker-Use Color Picker"
        case .screenAssistant: return "screenAssistant-Use Screen Assistant"
        case .downloads: return "downloads-Use Download Alerts"
        case .shortcuts: return "shortcuts-Use Shortcuts"
        default: return tab.highlightID(for: tab.title)
        }
    }
}

/// The status line under a page's title, for pages that have one.
private struct SettingsTabStatus: View {
    let tab: SettingsTab
    @ObservedObject private var orbit = Orbit.shared
    @ObservedObject private var agentHub = AgentHub.shared
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @Default(.enableOrbit) private var orbitOn
    @Default(.enableAgentsFeature) private var agentsOn
    @Default(.enableWhatsAppFeature) private var whatsAppOn

    var body: some View {
        switch tab {
        case .orbit where orbitOn:
            if orbit.isRunning {
                SettingsStatus(text: "Running · \(orbit.state.projects.count) projects, \(orbit.state.people.count) people, \(orbit.state.events.count) events", kind: .ok)
            } else {
                SettingsStatus(text: "Paused: turn on a part below", kind: .warn)
            }
        case .agents where agentsOn:
            if agentHub.isBridgeRunning {
                SettingsStatus(text: "Listening for agents on this Mac only", kind: .ok)
            } else if let error = agentHub.bridgeError {
                SettingsStatus(text: error, kind: .error)
            } else {
                SettingsStatus(text: "Starting…")
            }
        case .whatsapp where whatsAppOn:
            switch whatsApp.state {
            case .connected: SettingsStatus(text: "Connected", kind: .ok)
            case .reconnecting: SettingsStatus(text: "Reconnecting…", kind: .warn)
            case .waitingForLink: SettingsStatus(text: "Not linked yet: scan the QR code below", kind: .warn)
            case .failed(let message): SettingsStatus(text: message, kind: .error)
            case .starting, .installing: SettingsStatus(text: "Starting…")
            case .notInstalled: SettingsStatus(text: "Not set up yet", kind: .warn)
            case .disabled: EmptyView()
            }
        default:
            EmptyView()
        }
    }
}

/// Restart and Quit, at the bottom of the sidebar on every page.
private struct SettingsAppControls: View {
    var body: some View {
        HStack(spacing: 8) {
            Button {
                AppRelauncher.restart()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .help("Quit NotchFlow and open it again")
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .help("Quit NotchFlow")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.primary)
        .labelStyle(.titleAndIcon)
    }
}
