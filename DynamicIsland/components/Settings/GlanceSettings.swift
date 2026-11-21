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
                                .foregroundStyle(.orange)
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
                    Text("Web pages stay loaded so the board appears at once. They keep their own sign-ins, separate from Safari and Chrome, on this Mac only. On battery they can be unloaded when the board closes, and load again next time.")
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
                    Text("That doesn't look like a web address.").font(.caption).foregroundStyle(.orange)
                }
                Picker("Reload every", selection: Binding(get: { panel.refreshMinutes },
                                                          set: { value in glance.updatePanel(panel.id) { $0.refreshMinutes = value } })) {
                    ForEach([1, 5, 15, 30, 60], id: \.self) { minutes in
                        Text(minutes == 60 ? "hour" : "\(minutes) min").tag(minutes)
                    }
                }
                Toggle("Phone layout (fits small panels)", isOn: Binding(get: { panel.mobileLayout },
                                                                        set: { value in glance.updatePanel(panel.id) { $0.mobileLayout = value } }))
            case .pdf:
                HStack {
                    Text(panel.address.isEmpty ? "No file" : (panel.address as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") {
                        let open = NSOpenPanel()
                        open.allowedContentTypes = [.pdf]
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

/// The board in Settings: drag panels to move or swap them, drag a corner to resize.
struct GlanceLayoutEditor: View {
    @ObservedObject private var glance = GlanceManager.shared
    @Binding var selected: UUID?
    @State private var dragging: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var resizing: UUID?
    @State private var resizeDelta: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let area = CGRect(origin: .zero, size: geometry.size)
            let cellWidth = area.width / CGFloat(GlancePolicy.columns)
            let cellHeight = area.height / CGFloat(GlancePolicy.rows)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25))
                ForEach(0..<(GlancePolicy.columns * GlancePolicy.rows), id: \.self) { index in
                    let cell = GlanceLayout.rect(for: GlanceRect(x: index % GlancePolicy.columns, y: index / GlancePolicy.columns, width: 1, height: 1),
                                                 in: area, gap: 6)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: cell.width, height: cell.height)
                        .offset(x: cell.minX, y: cell.minY)
                }
                ForEach(glance.activeBoard.panels.filter(\.isShown)) { panel in
                    let base = GlanceLayout.rect(for: panel.frame, in: area, gap: 6)
                    let rect = shownRect(panel, base: base, cellWidth: cellWidth, cellHeight: cellHeight)
                    tile(panel)
                        .frame(width: rect.width, height: rect.height)
                        .overlay(alignment: .bottomTrailing) { resizeHandle(panel, base: base, cellWidth: cellWidth, cellHeight: cellHeight) }
                        .offset(x: rect.minX, y: rect.minY)
                        .zIndex(dragging == panel.id || resizing == panel.id ? 1 : 0)
                        .onTapGesture { selected = panel.id }
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    dragging = panel.id
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let x = Int(((base.minX + value.translation.width) / cellWidth).rounded())
                                    let y = Int(((base.minY + value.translation.height) / cellHeight).rounded())
                                    glance.updateActive { GlancePolicy.moving(panel.id, toX: x, y: y, on: $0) }
                                    dragging = nil
                                    dragOffset = .zero
                                    selected = panel.id
                                }
                        )
                }
            }
        }
        .aspectRatio(CGFloat(GlancePolicy.columns) / CGFloat(GlancePolicy.rows) * 0.9, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func shownRect(_ panel: GlancePanel, base: CGRect, cellWidth: CGFloat, cellHeight: CGFloat) -> CGRect {
        var rect = base
        if dragging == panel.id { rect = rect.offsetBy(dx: dragOffset.width, dy: dragOffset.height) }
        if resizing == panel.id {
            rect.size.width = max(cellWidth - 6, rect.width + resizeDelta.width)
            rect.size.height = max(cellHeight - 6, rect.height + resizeDelta.height)
        }
        return rect
    }

    private func tile(_ panel: GlancePanel) -> some View {
        let isSelected = selected == panel.id
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(isSelected ? 0.45 : 0.28))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1))
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: panel.kind.symbol).font(.system(size: 16, weight: .semibold))
                    Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
    }

    private func resizeHandle(_ panel: GlancePanel, base: CGRect, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.accentColor, in: Circle())
            .padding(4)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        resizing = panel.id
                        resizeDelta = value.translation
                    }
                    .onEnded { value in
                        let width = Int(((base.width + 6 + value.translation.width) / cellWidth).rounded())
                        let height = Int(((base.height + 6 + value.translation.height) / cellHeight).rounded())
                        glance.updateActive { GlancePolicy.resizing(panel.id, width: width, height: height, on: $0) }
                        resizing = nil
                        resizeDelta = .zero
                        selected = panel.id
                    }
            )
            .help("Drag to resize")
    }
}
