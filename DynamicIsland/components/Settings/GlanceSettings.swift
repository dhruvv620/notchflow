// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Glance: the shortcut, your layouts, which panels are on the
/// board, and a board to arrange them on by dragging.
struct GlanceSettings: View {
    @ObservedObject private var glance = GlanceManager.shared
    @Default(.enableGlance) private var enableGlance
    @Default(.glanceTrigger) private var trigger
    @Default(.glanceMode) private var mode
    @Default(.glanceBackdrop) private var backdrop
    @Default(.glanceBrowser) private var browser
    @Default(.glanceLivePicture) private var livePicture

    private var installedBrowsers: [GlancePolicy.Browser] {
        GlancePolicy.browsers.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
    @State private var selectedPanel: UUID?
    @State private var newClock = GlanceClocks.common[0].zone
    @State private var windowChoices: [GlanceLiveWindows.Choice] = []
    @State private var symbolsText = ""

    private var board: GlanceBoard { glance.activeBoard }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableGlance) {
                    Text("Use Glance")
                }
                .settingsHighlight(id: "glance-Use Glance")
                if enableGlance {
                    HStack {
                        Text("Opens with")
                        Spacer()
                        if glance.isRecordingKey {
                            Text("Press a key: Left Shift, fn, Right ⌘… or a shortcut. Esc cancels.")
                                .font(.caption)
                                .foregroundStyle(SettingsPalette.warn)
                            Button("Cancel") { glance.cancelRecordingKey() }
                        } else {
                            Picker("", selection: $trigger) {
                                ForEach(GlancePolicy.Trigger.allCases, id: \.rawValue) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button("Record Key…") { glance.startRecordingKey() }
                        }
                    }
                    .settingsHighlight(id: "glance-Hold to glance")
                    if trigger == GlancePolicy.Trigger.shortcut.rawValue {
                        KeyboardShortcuts.Recorder("Shortcut:", name: .glanceHold)
                    }
                    Picker("Behaviour", selection: $mode) {
                        ForEach(GlancePolicy.Mode.allCases, id: \.rawValue) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Picker("Behind the panels", selection: $backdrop) {
                        ForEach(GlancePolicy.Backdrop.allCases, id: \.rawValue) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack(alignment: .top) {
                        Text(triggerHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Glance") { glance.show(pinned: true) }
                    }
                }
            } header: {
                Text("Glance")
            }

            if enableGlance {
                layoutSection
                displaysSection
                panelsSection
                if let id = selectedPanel, let panel = board.panels.first(where: { $0.id == id }) {
                    panelSection(panel)
                }
                Section {
                    Picker("Open web pages in", selection: $browser) {
                        Text("Automatic (\(GlanceRealWindows.browser?.name ?? "built-in"))").tag("auto")
                        ForEach(installedBrowsers, id: \.bundleID) { browser in
                            Text(browser.name).tag(browser.bundleID)
                        }
                        Text("NotchFlow's own pages").tag("builtIn")
                    }
                    .settingsHighlight(id: "glance-Open web pages in")
                    Toggle("App windows as live pictures (uses Screen Recording)", isOn: $livePicture)
                    Defaults.Toggle(key: .glanceHideAds) {
                        Text("Hide ads and cookie banners")
                    }
                    .settingsHighlight(id: "glance-Hide ads and cookie banners")
                    Defaults.Toggle(key: .glanceUnloadOnBattery) {
                        Text("Unload web pages on battery")
                    }
                } header: {
                    Text("Web pages")
                } footer: {
                    Text("In your browser, web pages are its own windows, signed in as you: Chrome, Chrome Beta, Edge, Brave and Vivaldi show just the page; Safari shows a normal window. They move onto the board when it opens and wait just off screen in between. App windows are the apps' real windows, moved onto the board and back, so no screen recording is needed. A window on another desktop can't be moved here; set its app to All Desktops (right-click its Dock icon › Options). NotchFlow's own pages keep their own sign-ins and can hide ads and cookie banners.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: selectedPanel) { _, _ in symbolsText = "" }
    }

    private var triggerHelp: String {
        let key = GlancePolicy.Trigger(rawValue: trigger) ?? .shortcut
        let name = key == .shortcut ? "the shortcut" : key.title.replacingOccurrences(of: " (either)", with: "")
        var text: String
        switch GlancePolicy.Mode(rawValue: mode) ?? .holdOrTap {
        case .holdOrTap:
            text = "Hold \(name) to peek at your boards (point at and click panels while holding), let go and they're gone. Tap it instead to keep them open; tap again or Esc to close."
        case .hold:
            text = "Hold \(name) to see your boards over everything; you can point at and click panels while holding it. Let go and they're gone."
        case .toggle:
            text = "Press \(name) to show your boards, press it again (or Esc) to hide them."
        }
        if key != .shortcut {
            text += " On its own only: \(name) with another key (typing a capital, a shortcut) never opens Glance."
        }
        if key == .fn {
            text += " Set System Settings › Keyboard › \"Press 🌐 key to\" to Do Nothing, so the emoji picker doesn't open too."
        }
        if key != .shortcut && !AXIsProcessTrusted() {
            text += " NotchFlow needs Accessibility to notice the key."
        }
        return text
    }

    // MARK: Layouts

    private var layoutSection: some View {
        Section {
            HStack {
                Picker("Layout", selection: Binding(get: { glance.activeBoardID }, set: { glance.selectBoard($0) })) {
                    ForEach(glance.boards) { board in
                        Text(board.name).tag(board.id)
                    }
                }
                .frame(maxWidth: 260)
                Spacer()
                Button("New") { glance.newBoard(); selectedPanel = nil }
                Button("Duplicate") { glance.duplicateActive(); selectedPanel = nil }
                Button("Delete", role: .destructive) { glance.deleteActive(); selectedPanel = nil }
                    .disabled(glance.boards.count < 2)
            }
            .settingsHighlight(id: "glance-Layouts")
            TextField("Name", text: Binding(get: { board.name }, set: { glance.renameActive($0) }))

            VStack(alignment: .leading, spacing: 6) {
                Text("Ready-made arrangements").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(GlancePolicy.presets) { preset in
                        Button {
                            glance.updateActive { GlancePolicy.applying(preset, to: $0) }
                        } label: {
                            VStack(spacing: 4) {
                                GlancePresetThumbnail(preset: preset)
                                    .frame(width: 72, height: 45)
                                Text(preset.name).font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Arrange the panels as \(preset.name)")
                    }
                }
            }

            GlanceLayoutEditor(selected: $selectedPanel)
                .padding(.vertical, 4)
            Text("Drag a panel to move it (drop it on another to swap them), drag its corner to resize it, click it to change it below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Layout")
        }
    }

    // MARK: Displays

    private var displaysSection: some View {
        Section {
            Defaults.Toggle(key: .glanceSameOnAllDisplays) {
                Text("Same layout on all displays")
            }
            ForEach(NSScreen.screens, id: \.self) { screen in
                let key = GlanceManager.key(for: screen)
                Picker(selection: Binding(get: { glance.displayBoards[key] },
                                          set: { glance.setBoard($0, forDisplay: key) })) {
                    Text("Selected layout").tag(UUID?.none)
                    ForEach(glance.boards) { board in
                        Text(board.name).tag(UUID?.some(board.id))
                    }
                } label: {
                    Label(screen.localizedName, systemImage: screen == NSScreen.screens.first ? "laptopcomputer" : "display")
                }
            }
        } header: {
            Text("Displays")
        } footer: {
            Text("Give each display its own layout. When Glance opens, the display with the pointer shows its layout, and every other display with a layout of its own shows that one too. \"Selected layout\" shows the layout picked above, on the display with the pointer only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsHighlight(id: "glance-Displays")
    }

    // MARK: Panels

    private var panelsSection: some View {
        Section {
            ForEach(GlancePanelKind.allCases.filter(\.isBuiltIn), id: \.self) { kind in
                Toggle(isOn: Binding(get: { board.panels.contains { $0.kind == kind && $0.isShown } },
                                     set: { setBuiltIn(kind, shown: $0) })) {
                    Label(kind.defaultTitle, systemImage: kind.symbol)
                }
            }
            ForEach(board.panels.filter { !$0.kind.isBuiltIn }) { panel in
                HStack {
                    Toggle(isOn: Binding(get: { panel.isShown },
                                         set: { shown in glance.updateActive { GlancePolicy.setting(panel.id, shown: shown, on: $0) } })) {
                        Label(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title, systemImage: panel.kind.symbol)
                    }
                    Button("Edit") { selectedPanel = panel.id }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        if selectedPanel == panel.id { selectedPanel = nil }
                        glance.updateActive { GlancePolicy.removing(panel.id, from: $0) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add on the Board…") {
                    glance.startEditing()
                    glance.launcherDisplay = NSScreen.main.map(GlanceManager.key(for:))
                }
                .buttonStyle(.borderedProminent)
                Button("Add Web Page") {
                    glance.updateActive { GlancePolicy.adding(.web, to: $0) }
                    selectedPanel = glance.activeBoard.panels.last?.id
                }
                Button("Add PDF…") { addPDF() }
                Menu("Add App Window") {
                    if windowChoices.isEmpty {
                        Text("No windows found. Allow Screen Recording for NotchFlow, then try again.")
                    }
                    ForEach(windowChoices) { choice in
                        Button(choice.title.isEmpty ? choice.appName : "\(choice.appName) · \(choice.title)") { addWindow(choice) }
                    }
                }
                .fixedSize()
                Spacer()
            }
            Text("A panel switched on goes where there's room; when the board is full, make room by resizing or switching another off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Panels")
        }
        .settingsHighlight(id: "glance-Panels")
        .task { windowChoices = await GlanceLiveWindows.shared.choices() }
    }

    private func addWindow(_ choice: GlanceLiveWindows.Choice) {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        glance.updateActive { board in
            var board = GlancePolicy.adding(.window, title: choice.appName, to: board)
            if let index = board.panels.indices.last {
                board.panels[index].windowApp = choice.bundleID
                board.panels[index].windowTitle = choice.title
            }
            return board
        }
        selectedPanel = glance.activeBoard.panels.last?.id
    }

    private func setBuiltIn(_ kind: GlancePanelKind, shown: Bool) {
        if let panel = board.panels.first(where: { $0.kind == kind }) {
            glance.updateActive { GlancePolicy.setting(panel.id, shown: shown, on: $0) }
        } else if shown {
            glance.updateActive { GlancePolicy.adding(kind, to: $0) }
        }
    }

    private func addPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        glance.updateActive { GlancePolicy.adding(.pdf, title: url.deletingPathExtension().lastPathComponent, address: url.path, to: $0) }
        selectedPanel = glance.activeBoard.panels.last?.id
    }

    private func saveSymbols(_ panel: GlancePanel) {
        guard !symbolsText.isEmpty else { return }
        let symbols = GlancePolicy.symbols(from: symbolsText)
        glance.updatePanel(panel.id) { $0.symbols = symbols }
        symbolsText = ""
    }

    // MARK: The selected panel

    @ViewBuilder
    private func panelSection(_ panel: GlancePanel) -> some View {
        Section {
            TextField("Title", text: Binding(get: { panel.title }, set: { value in glance.updatePanel(panel.id) { $0.title = value } }))
            switch panel.kind {
            case .web:
                TextField("Address", text: Binding(get: { panel.address }, set: { value in glance.updatePanel(panel.id) { $0.address = value } }),
                          prompt: Text("mail.google.com"))
                if !panel.address.isEmpty, GlancePolicy.webURL(panel.address) == nil {
                    Text("That doesn't look like a web address.").font(.caption).foregroundStyle(SettingsPalette.warn)
                }
                Picker("Reload every", selection: Binding(get: { panel.refreshMinutes },
                                                          set: { value in glance.updatePanel(panel.id) { $0.refreshMinutes = value } })) {
                    ForEach([1, 5, 15, 30, 60], id: \.self) { minutes in
                        Text(minutes == 60 ? "hour" : "\(minutes) min").tag(minutes)
                    }
                }
                Toggle("Phone layout (fits small panels)", isOn: Binding(get: { panel.mobileLayout },
                                                                        set: { value in glance.updatePanel(panel.id) { $0.mobileLayout = value } }))
            case .weather:
                TextField("City", text: Binding(get: { panel.address }, set: { value in glance.updatePanel(panel.id) { $0.address = value } }),
                          prompt: Text("Pune"))
            case .calendar, .reminders:
                Picker("Show", selection: Binding(get: { panel.view.isEmpty ? (panel.kind.views.first?.id ?? "") : panel.view },
                                                  set: { value in glance.updatePanel(panel.id) { $0.view = value } })) {
                    ForEach(panel.kind.views, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)
            case .pdf, .html:
                HStack {
                    Text(panel.address.isEmpty ? "No file" : (panel.address as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") {
                        let open = NSOpenPanel()
                        open.allowedContentTypes = panel.kind == .pdf ? [.pdf] : [.html]
                        if open.runModal() == .OK, let url = open.url {
                            glance.updatePanel(panel.id) { $0.address = url.path }
                        }
                    }
                }
            case .clocks:
                ForEach(panel.timeZones, id: \.self) { zone in
                    HStack {
                        Text(GlanceClocks.cityName(zone))
                        Spacer()
                        Button(role: .destructive) {
                            glance.updatePanel(panel.id) { $0.timeZones.removeAll { $0 == zone } }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("Add a city", selection: $newClock) {
                        ForEach(GlanceClocks.common, id: \.zone) { city in
                            Text(city.name).tag(city.zone)
                        }
                    }
                    Button("Add") {
                        glance.updatePanel(panel.id) { if !$0.timeZones.contains(newClock) { $0.timeZones.append(newClock) } }
                    }
                }
            case .stocks:
                TextField("Symbols", text: Binding(get: { symbolsText.isEmpty ? panel.symbols.joined(separator: ", ") : symbolsText },
                                                   set: { symbolsText = $0 }),
                          prompt: Text("AAPL, RELIANCE.NS, ^NSEI, BTC-USD"))
                    .onSubmit { saveSymbols(panel) }
                HStack {
                    Text("Yahoo Finance symbols: Indian stocks end in .NS (NSE) or .BO (BSE), indexes start with ^ (^NSEI, ^BSESN, ^GSPC), crypto ends in -USD. Prices refresh every minute while the board is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { saveSymbols(panel) }
                }
            case .window:
                Picker("Window", selection: Binding(get: { windowChoices.first { $0.bundleID == panel.windowApp && $0.title == panel.windowTitle } },
                                                    set: { choice in
                                                        guard let choice else { return }
                                                        glance.updatePanel(panel.id) {
                                                            $0.windowApp = choice.bundleID
                                                            $0.windowTitle = choice.title
                                                            if $0.title.isEmpty || $0.title == GlancePanelKind.window.defaultTitle { $0.title = choice.appName }
                                                        }
                                                    })) {
                    Text(panel.windowApp.isEmpty ? "Choose a window" : "\(panel.title) (not open now)").tag(GlanceLiveWindows.Choice?.none)
                    ForEach(windowChoices) { choice in
                        Text(choice.title.isEmpty ? choice.appName : "\(choice.appName) · \(choice.title)").tag(GlanceLiveWindows.Choice?.some(choice))
                    }
                }
                HStack {
                    Text("The window shows live while the board is open (Screen Recording must be allowed). If its title changes, the closest match from the same app is shown. Click it on the board to go to it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh List") { Task { windowChoices = await GlanceLiveWindows.shared.choices() } }
                }
            default:
                EmptyView()
            }
            HStack {
                Spacer()
                Button("Remove from Board", role: .destructive) {
                    selectedPanel = nil
                    if panel.kind.isBuiltIn {
                        glance.updateActive { GlancePolicy.setting(panel.id, shown: false, on: $0) }
                    } else {
                        glance.updateActive { GlancePolicy.removing(panel.id, from: $0) }
                    }
                }
            }
        } header: {
            Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
        }
    }
}

/// A small drawing of a preset's slots.
struct GlancePresetThumbnail: View {
    let preset: GlancePreset

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
                ForEach(Array(preset.slots.enumerated()), id: \.offset) { _, slot in
                    let rect = GlanceLayout.rect(for: slot, in: CGRect(origin: .zero, size: geometry.size), gap: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}

/// The board in Settings: the same arranging as on the board itself.
struct GlanceLayoutEditor: View {
    @ObservedObject private var glance = GlanceManager.shared
    @Binding var selected: UUID?

    var body: some View {
        GlanceArranger(board: glance.activeBoard, gap: 5, cornerRadius: 8, selected: $selected,
                       change: { glance.updateActive($0) },
                       tile: { panel in
                           RoundedRectangle(cornerRadius: 8, style: .continuous)
                               .fill(Color.accentColor.opacity(selected == panel.id ? 0.45 : 0.28))
                               .overlay {
                                   VStack(spacing: 3) {
                                       Image(systemName: panel.kind.symbol).font(.system(size: 14, weight: .semibold))
                                       Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                                           .font(.system(size: 10, weight: .medium))
                                           .lineLimit(1)
                                           .padding(.horizontal, 4)
                                   }
                                   .foregroundStyle(.white)
                               }
                       })
            .padding(6)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }
}
