/*
 * NotchFlow
 * Copyright (C) 2026 dhruvv620
 * Portions Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for NotchFlow
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

import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, accentColor: Color? = nil) {
        self.id = NotchBuiltinTab.identifier(for: view)
        self.label = label
        self.icon = icon
        self.view = view
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject private var preferences = NotchTabPreferences.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    // The temporary Copied tab comes and goes with the clipboard.
    @ObservedObject private var copyActions = CopyActionManager.shared
    @Default(.enableAgentsFeature) private var enableAgentsFeature
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableRemindersFeature) private var enableRemindersFeature
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
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
        if Defaults[.enableCuelyFeature] {
            tabsArray.append(TabModel(label: "Cuely", icon: "text.quote", view: .cuely))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if Defaults[.enableRemindersFeature] {
            tabsArray.append(TabModel(label: "Todos", icon: "checklist", view: .reminders))
        }
        if Defaults[.communicationsEnabled] {
            tabsArray.append(TabModel(label: "Notifications", icon: "bell.badge", view: .notifications))
        }
        if Defaults[.enableWhatsAppFeature] {
            tabsArray.append(TabModel(label: "WhatsApp", icon: "message.fill", view: .whatsapp))
        }
        if Defaults[.showCalendar] {
            tabsArray.append(TabModel(label: "Calendar", icon: "calendar", view: .calendar))
        }
        if Defaults[.enableAgentsFeature] {
            tabsArray.append(TabModel(label: "AI Agents", icon: "sparkles", view: .agents))
        }
        if Defaults[.timeTrackingEnabled] || Defaults[.enableWorkspaces] {
            tabsArray.append(TabModel(label: "Flow", icon: "clock.badge.checkmark", view: .flow))
        }
        return tabsArray
    }
    static var availableTabs: [TabModel] {
        let candidates = candidateTabs
        if Defaults[.enableMinimalisticUI] { return Array(candidates.filter { $0.view == .home }.prefix(1)) }
        let ids = NotchTabOrderPolicy.visibleIDs(order: Defaults[.notchTabOrder], hidden: Defaults[.notchHiddenTabs],
                                               available: candidates.map(\.id), fallback: NotchBuiltinTab.music.rawValue)
        let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let ordered = ids.compactMap { lookup[$0] }
        // A temporary tab for something just copied comes first while it lasts.
        if CopyActionManager.hasLiveSuggestion {
            return [TabModel(label: "Copied", icon: "doc.on.clipboard.fill", view: .copyAction)] + ordered
        }
        return ordered
    }

    static func validateCurrentSelection() {
        let tabs = availableTabs
        let coordinator = DynamicIslandViewCoordinator.shared
        let selected = tabs.contains { $0.view == coordinator.currentView }
        guard !selected, let first = tabs.first else { return }
        coordinator.currentView = first.view
    }

    static func advanceTab(forward: Bool) {
        let coordinator = DynamicIslandViewCoordinator.shared
        let tabs = availableTabs
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.view == coordinator.currentView }
        let index = current.map { ($0 + (forward ? 1 : tabs.count - 1)) % tabs.count } ?? 0
        let target = tabs[index]
        withAnimation(.easeInOut(duration: 0.2)) {
            coordinator.currentView = target.view
            coordinator.tabSwitchForward = forward
        }
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        let selected = isSelected(tab)
                        Button {
                            // Animate the height change between tabs as well as the content.
                            withAnimation(.smooth(duration: NotchTabHeightPolicy.animationDuration)) {
                                coordinator.currentView = tab.view
                            }
                            NotificationCenter.default.post(name: .notchTabExplicitSelection, object: nil)
                        } label: {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(selected ? (tab.accentColor ?? appearance.accentColor) : Color.white.opacity(0.62))
                                .frame(width: 28, height: 28)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            if tab.view == .whatsapp && whatsApp.totalUnread > 0 {
                                Circle()
                                    .fill(Color.whatsAppGreen)
                                    .frame(width: 7, height: 7)
                                    .offset(x: -3, y: 4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background {
                            if selected {
                                Capsule().fill(Color.white.opacity(0.10))
                                    .matchedGeometryEffect(id: "selection", in: animation)
                            }
                        }
                        .id(tab.id)
                        .help(tab.label).accessibilityLabel(tab.label)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 30)
            .onChange(of: coordinator.currentView) { _, _ in
                revealSelection(using: reader)
            }
            .onAppear { ensureValidSelection(with: tabs); revealSelection(using: reader) }
            .onReceive(NotificationCenter.default.publisher(for: .notchTabsDidChange)) { _ in
                Self.validateCurrentSelection(); revealSelection(using: reader)
            }
        }
    }

    private func revealSelection(using reader: ScrollViewProxy) {
        guard let selected = tabs.first(where: { isSelected($0) }) else { return }
        withAnimation(.smooth(duration: 0.28)) { reader.scrollTo(selected.id, anchor: .center) }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
