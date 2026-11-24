// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct NotchTabsSettingsView: View {
    let openSettings: (String) -> Void
    @ObservedObject private var preferences = NotchTabPreferences.shared
    @Default(.enableMinimalisticUI) private var minimalistic
    @Default(.notchTabOrder) private var tabOrder
    /// The tab being dragged in the list, if any.
    @State private var draggingID: String?
    private var descriptors: [TabModel] {
        let all = preferences.orderedBuiltins.map { TabModel(label: $0.title, icon: $0.symbol, view: $0.view) }
        let ids = NotchTabOrderPolicy.normalizedOrder(Defaults[.notchTabOrder], known: all.map(\.id))
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    var body: some View {
        Form {
            if minimalistic {
                Section {
                    HStack {
                        SettingsStatus(text: "Minimal mode shows only Music. These tabs are for the standard layout.", kind: .warn)
                        Spacer()
                        Button("Use Standard Layout") { minimalistic = false }
                    }
                }
            }
            Section {
                ForEach(descriptors) { tab in
                    tabRow(tab)
                        .opacity(draggingID == tab.id ? 0.4 : 1)
                        .onDrag {
                            draggingID = tab.id
                            return NSItemProvider(object: tab.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: TabRowDropDelegate(
                            target: tab.id,
                            dragging: $draggingID,
                            ids: descriptors.map(\.id),
                            preferences: preferences
                        ))
                }
                HStack {
                    Spacer()
                    Button("Reset Order") { preferences.reset() }
                }
            } header: {
                Text("Tabs, in order")
            } footer: {
                Text("Drag a row by its handle (or use the arrows) to change the order. Hiding a tab only removes its icon; the feature keeps running.")
            }
            .settingsHighlight(id: "tabsAndFeatures-Tab visibility and order")

            featureControls
        }
        // A drop anywhere else on the page ends the drag, so no row stays faded.
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            draggingID = nil
            return false
        }
    }

    private func tabRow(_ tab: TabModel) -> some View {
        let available = TabSelectionView.candidateTabs.contains { $0.id == tab.id }
        let ids = descriptors.map(\.id)
        let index = ids.firstIndex(of: tab.id) ?? 0
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
            Image(systemName: tab.icon).frame(width: 20).foregroundStyle(available ? Color.accentColor : Color.secondary)
            SettingsRowLabel(title: tab.label, detail: available ? nil : "Its feature is off. Turn it on below.")
            Spacer()
            Button { moveUp(tab.id) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(index == 0).help("Move up")
            Button { moveDown(tab.id) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(index + 1 >= ids.count).help("Move down")
            Toggle("Show \(tab.label)", isOn: Binding(get: { preferences.isShown(tab.id) }, set: { preferences.setShown($0, id: tab.id) }))
                .labelsHidden()
                .help(available ? "Show or hide this tab" : "Shows once its feature is on")
        }
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

    @ViewBuilder private var featureControls: some View {
        Section {
            featureRow("Music", symbol: "music.note", destination: "media") {
                Text("Always on").font(.caption).foregroundStyle(.secondary)
            }
            featureToggle("Shelf", symbol: "tray.fill", key: .dynamicShelf, destination: "shelf")
            featureToggle("Timers", symbol: "timer", key: .enableTimerFeature, destination: "timer")
            if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] != .tab {
                HStack {
                    SettingsStatus(text: "Timers open outside the tab bar now.")
                    Spacer()
                    Button("Use a Timers Tab") { Defaults[.timerDisplayMode] = .tab }
                }
                .padding(.leading, 30)
            }
            featureToggle("Calendar", symbol: "calendar", key: .showCalendar, destination: "calendar")
            featureToggle("Todos", symbol: "checklist", key: .enableRemindersFeature, destination: "calendar")
            featureToggle("Notifications & Calls", symbol: "bell.badge", key: .communicationsEnabled, destination: "communications")
            featureToggle("WhatsApp", symbol: "message.fill", key: .enableWhatsAppFeature, destination: "whatsapp")
            featureToggle("AI Agents", symbol: "sparkles", key: .enableAgentsFeature, destination: "agents")
            featureToggle("Clipboard", symbol: "doc.on.clipboard", key: .enableClipboardManager, destination: "clipboard")
            featureToggle("Cuely", symbol: "text.quote", key: .enableCuelyFeature, destination: nil)
            featureToggle("Notes", symbol: "note.text", key: .enableNotes, destination: "notes")
            featureToggle("Stats", symbol: "chart.xyaxis.line", key: .enableStatsFeature, destination: "stats")
            featureToggle("AI usage", symbol: "chart.bar.doc.horizontal", key: .enableLLMUsageFeature, destination: "stats")
            featureToggle("Terminal", symbol: "apple.terminal", key: .enableTerminalFeature, destination: "terminal")
        } header: {
            Text("Features with a tab")
        } footer: {
            Text("The same switches as on each feature's own page. The slider button opens that page.")
        }
        .settingsHighlight(id: "tabsAndFeatures-Notch feature controls")

        Section {
            featureToggle("Upcoming reminders", symbol: "calendar.badge.clock", key: .enableReminderLiveActivity, destination: "calendar")
            featureToggle("Meeting countdown", symbol: "video.fill", key: .enableMeetingCountdown, destination: "calendar")
            featureToggle("Download alerts", symbol: "arrow.down.circle", key: .enableDownloadListener, destination: "downloads")
            featureToggle("Copy-to-action", symbol: "doc.on.clipboard.fill", key: .enableCopyActions, destination: "smartTools")
            featureToggle("Distraction meter", symbol: "eye.trianglebadge.exclamationmark", key: .enableFocusGuard, destination: "smartTools")
            featureToggle("Build watcher", symbol: "hammer", key: .enableBuildWatcher, destination: "smartTools")
            featureToggle("Volume and brightness", symbol: "speaker.wave.2", key: .enableSystemHUD, destination: "hudAndOSD")
        } header: {
            Text("In the closed notch")
        }

        Section {
            featureToggle("Color Picker", symbol: "eyedropper", key: .enableColorPickerFeature, destination: "colorPicker")
            featureToggle("Smart replies", symbol: "sparkles", key: .enableSmartReplies, destination: "smartTools")
        } header: {
            Text("Tools")
        }
    }

    private func featureToggle(_ title: String, symbol: String, key: Defaults.Key<Bool>, destination: String?) -> some View {
        featureRow(title, symbol: symbol, destination: destination) {
            Defaults.Toggle(key: key) { Text(title) }.labelsHidden()
        }
    }
    private func featureRow<Control: View>(_ title: String, symbol: String, destination: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
            control()
            if let destination {
                Button { openSettings(destination) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).help("Configure \(title)")
            } else {
                // Options for this feature live in its tab; keep the switches aligned.
                Image(systemName: "slider.horizontal.3").hidden()
            }
        }
    }
}

/// Moves the dragged tab into place as it passes over each row.
private struct TabRowDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let ids: [String]
    let preferences: NotchTabPreferences

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            preferences.move(source, over: target, knownIDs: ids)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}
