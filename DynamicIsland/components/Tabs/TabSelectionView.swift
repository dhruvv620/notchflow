/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? NotchBuiltinTab.identifier(for: view)
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject private var preferences = NotchTabPreferences.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableRemindersFeature) private var enableRemindersFeature
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation
    
    private var tabs: [TabModel] { Self.availableTabs }

    static var candidateTabs: [TabModel] {
        var tabsArray: [TabModel] = []

        tabsArray.append(TabModel(label: "Music", icon: "music.note", view: .home))

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab {
            tabsArray.append(TabModel(label: "Timers", icon: "timer", view: .timer))
        }

        // Stats tab only shown when stats feature is enabled
        if Defaults[.enableStatsFeature] {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        // Usage tab only shown when LLM usage feature is enabled
        if Defaults[.enableLLMUsageFeature] {
            tabsArray.append(TabModel(label: "Usage", icon: "chart.bar.doc.horizontal", view: .llmUsage))
        }

        if Defaults[.enableNotes] {
            tabsArray.append(TabModel(label: "Notes", icon: "note.text", view: .notes))
        }
        if Defaults[.enableClipboardManager] {
            tabsArray.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if Defaults[.enableRemindersFeature] {
            tabsArray.append(TabModel(label: "Todos", icon: "checklist", view: .reminders))
        }
        if Defaults[.showCalendar] {
            tabsArray.append(TabModel(label: "Calendar", icon: "calendar", view: .calendar))
        }
        if Defaults[.enableThirdPartyExtensions] && Defaults[.enableExtensionNotchExperiences] && Defaults[.enableExtensionNotchTabs] {
            for payload in ExtensionNotchExperienceManager.shared.activeExperiences.filter({ $0.descriptor.tab != nil }) {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }
    static var availableTabs: [TabModel] {
        let candidates = candidateTabs
        if Defaults[.enableMinimalisticUI] { return Array(candidates.filter { $0.view == .home }.prefix(1)) }
        let ids = NotchTabOrderPolicy.visibleIDs(order: Defaults[.notchTabOrder], hidden: Defaults[.notchHiddenTabs],
                                               available: candidates.map(\.id), fallback: NotchBuiltinTab.music.rawValue)
        let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    static func validateCurrentSelection() {
        let tabs = availableTabs
        let coordinator = DynamicIslandViewCoordinator.shared
        let selected = tabs.contains { $0.view == coordinator.currentView && ($0.view != .extensionExperience || $0.experienceID == coordinator.selectedExtensionExperienceID) }
        guard !selected, let first = tabs.first else { return }
        coordinator.selectedExtensionExperienceID = first.experienceID
        coordinator.currentView = first.view
    }

    static func advanceTab(forward: Bool) {
        let coordinator = DynamicIslandViewCoordinator.shared
        let tabs = availableTabs
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex {
            $0.view == coordinator.currentView && ($0.view != .extensionExperience || $0.experienceID == coordinator.selectedExtensionExperienceID)
        }
        let index = current.map { ($0 + (forward ? 1 : tabs.count - 1)) % tabs.count } ?? 0
        let target = tabs[index]
        withAnimation(.easeInOut(duration: 0.2)) {
            coordinator.selectedExtensionExperienceID = target.experienceID
            coordinator.currentView = target.view
            coordinator.tabSwitchForward = forward
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabButtons
            Menu {
                ForEach(tabs) { tab in
                    Button {
                        coordinator.selectedExtensionExperienceID = tab.experienceID
                        coordinator.currentView = tab.view
                    } label: { Label(tab.label, systemImage: tab.icon) }
                }
            } label: {
                Label(tabs.first(where: { isSelected($0) })?.label ?? "Tabs",
                      systemImage: tabs.first(where: { isSelected($0) })?.icon ?? "square.grid.2x2")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .onAppear { ensureValidSelection(with: tabs) }
        .onReceive(NotificationCenter.default.publisher(for: .notchTabsDidChange)) { _ in Self.validateCurrentSelection() }
        .onChange(of: enableRemindersFeature) { _, _ in ensureValidSelection(with: tabs) }
        .onChange(of: enableClipboardManager) { _, _ in ensureValidSelection(with: tabs) }
    }

    private var tabButtons: some View {
        HStack(spacing: tabs.count > 4 ? 16 : 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? appearance.accentColor

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    if tab.view == .extensionExperience {
                        coordinator.selectedExtensionExperienceID = tab.experienceID
                    }
                    coordinator.currentView = tab.view
                }
                .help(tab.label)
                .accessibilityLabel(tab.label)
                .frame(height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? appearance.accentColor).opacity(0.18))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }

                
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
        .onChange(of: enableRemindersFeature) { _, _ in
            ensureValidSelection(with: tabs)
        }
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
