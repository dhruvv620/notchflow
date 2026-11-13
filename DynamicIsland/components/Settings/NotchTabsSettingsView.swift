// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

struct NotchTabsSettingsView: View {
    let openSettings: (String) -> Void
    @ObservedObject private var preferences = NotchTabPreferences.shared
    @ObservedObject private var extensions = ExtensionNotchExperienceManager.shared
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @Default(.enableMinimalisticUI) private var minimalistic
    @State private var segment = Segment.tabs

    private enum Segment: String, CaseIterable, Identifiable {
        case tabs = "Tabs", features = "Features"
        var id: String { rawValue }
    }
    private var descriptors: [TabModel] {
        let candidates = TabSelectionView.candidateTabs
        let extensionTabs = candidates.filter { $0.experienceID != nil }
        let builtins = preferences.orderedBuiltins.map { TabModel(label: $0.title, icon: $0.symbol, view: $0.view) }
        let all = builtins + extensionTabs
        let ids = NotchTabOrderPolicy.normalizedOrder(Defaults[.notchTabOrder], known: all.map(\.id))
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Tabs and features", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
                .settingsHighlight(id: "tabsAndFeatures-Tabs & Features")
                .padding(.horizontal, 20)
                .padding(.top, 20)
            if minimalistic {
                HStack {
                    Text("Tab choices apply to Standard layout. Minimalistic layout keeps its single Music view.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Standard layout") { minimalistic = false }
                }.padding(.horizontal, 20)
            }
            switch segment {
            case .tabs:
                tabEditor
            case .features:
                ScrollView { featureControls.padding(.horizontal, 20).padding(.bottom, 20) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(highlightCoordinator.$activeHighlightID) { id in
            if id == "tabsAndFeatures-Notch feature controls" { segment = .features }
            if id == "tabsAndFeatures-Tab visibility and order" { segment = .tabs }
        }
    }

    private var tabEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag a row to reorder the icons, swipes and page indicators.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
            List {
                ForEach(descriptors) { tab in tabRow(tab) }
                    .onMove { offsets, destination in
                        preferences.moveRows(from: offsets, to: destination, displayedIDs: descriptors.map(\.id))
                    }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            HStack {
                Text("Hiding a tab keeps its position and leaves its feature running. Music is the fallback when all tabs are hidden.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset tab layout") { preferences.reset() }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .settingsHighlight(id: "tabsAndFeatures-Tab visibility and order")
    }

    private func tabRow(_ tab: TabModel) -> some View {
        let available = TabSelectionView.candidateTabs.contains { $0.id == tab.id }
        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                .help("Drag to reorder")
            Image(systemName: tab.icon).frame(width: 20).foregroundStyle(available ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.label).font(.system(size: 13, weight: .medium))
                if !available { Text("Feature is off — enable it in Features").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle("Show \(tab.label)", isOn: Binding(get: { preferences.isShown(tab.id) }, set: { preferences.setShown($0, id: tab.id) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .help(available ? "Show or hide this tab" : "Show this tab when its feature is enabled")
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityLabel("\(tab.label), \(preferences.isShown(tab.id) ? "shown" : "hidden")")
        .accessibilityAction(named: Text("Move up")) { moveUp(tab.id) }
        .accessibilityAction(named: Text("Move down")) { moveDown(tab.id) }
    }

    private func moveUp(_ id: String) {
        let ids = descriptors.map(\.id)
        guard let index = ids.firstIndex(of: id), index > 0 else { return }
        preferences.move(id, before: ids[index - 1], knownIDs: ids)
    }
    private func moveDown(_ id: String) {
        let ids = descriptors.map(\.id)
        guard let index = ids.firstIndex(of: id), index + 1 < ids.count else { return }
        preferences.move(id, over: ids[index + 1], knownIDs: ids)
    }

    private var featureControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Notch tabs") {
                VStack(spacing: 10) {
                    featureRow("Music", symbol: "music.note", destination: "media") {
                        Text("The default hover view").font(.caption).foregroundStyle(.secondary)
                    }
                    Group {
                    featureToggle("Shelf", symbol: "tray.fill", key: .dynamicShelf, destination: "shelf")
                    featureToggle("Timers", symbol: "timer", key: .enableTimerFeature, destination: "timer")
                    if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] != .tab {
                        HStack {
                            Text("Timers currently opens outside the tab bar.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Use Timers tab") { Defaults[.timerDisplayMode] = .tab }
                        }
                    }
                    featureToggle("Calendar", symbol: "calendar", key: .showCalendar, destination: "calendar")
                    }
                    featureToggle("Communications", symbol: "bell.badge", key: .communicationsEnabled, destination: "communications")
                    featureToggle("Todos", symbol: "checklist", key: .enableRemindersFeature, destination: "calendar")
                    featureToggle("Clipboard", symbol: "doc.on.clipboard", key: .enableClipboardManager, destination: "clipboard")
                    featureToggle("Notes", symbol: "note.text", key: .enableNotes, destination: "notes")
                    featureToggle("Stats", symbol: "chart.xyaxis.line", key: .enableStatsFeature, destination: "stats")
                    featureToggle("AI Usage", symbol: "chart.bar.doc.horizontal", key: .enableLLMUsageFeature, destination: "stats")
                    featureToggle("Terminal", symbol: "apple.terminal", key: .enableTerminalFeature, destination: "terminal")
                }.padding(6)
            }
            GroupBox("Quick tools and activities") {
                VStack(spacing: 10) {
                    featureToggle("Color picker", symbol: "eyedropper", key: .enableColorPickerFeature, destination: "colorPicker")
                    featureToggle("Download alerts", symbol: "arrow.down.circle", key: .enableDownloadListener, destination: "downloads")
                    featureToggle("System HUDs", symbol: "speaker.wave.2", key: .enableSystemHUD, destination: "hudAndOSD")
                    settingsLink("Appearance and size", symbol: "paintpalette", destination: "appearance")
                    settingsLink("Live activities", symbol: "waveform.path.ecg", destination: "liveActivities")
                    settingsLink("Calendar and Reminders access", symbol: "calendar", destination: "calendar")
                    settingsLink("Device and audio controls", symbol: "headphones", destination: "devices")
                    settingsLink("Battery", symbol: "battery.100", destination: "battery")
                    settingsLink("Keyboard shortcuts", symbol: "keyboard", destination: "shortcuts")
                }.padding(6)
            }
            Text("Turning Clipboard off stops collecting new copies. Tab visibility alone keeps the feature running.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .settingsHighlight(id: "tabsAndFeatures-Notch feature controls")
    }

    private func featureToggle(_ title: String, symbol: String, key: Defaults.Key<Bool>, destination: String) -> some View {
        featureRow(title, symbol: symbol, destination: destination) {
            Defaults.Toggle(key: key) { Text(title) }.labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
    private func settingsLink(_ title: String, symbol: String, destination: String) -> some View {
        featureRow(title, symbol: symbol, destination: destination) { EmptyView() }
    }
    private func featureRow<Control: View>(_ title: String, symbol: String, destination: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            control()
            Button { openSettings(destination) } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless).help("Configure \(title)")
        }
    }
}
