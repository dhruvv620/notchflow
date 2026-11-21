// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Adding to a board, on the board itself: a web page, a widget, an app's
/// window, or a file. What's added goes where there's room; drag it into
/// place after.
struct GlanceLauncher: View {
    let boardID: UUID
    let displayKey: String
    @ObservedObject private var glance = GlanceManager.shared

    private enum Tab: String, CaseIterable { case web = "Web", widgets = "Widgets", apps = "Apps", files = "Files" }
    @State private var tab: Tab = .web

    private var board: GlanceBoard? { glance.boards.first { $0.id == boardID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
                Button {
                    glance.launcherDisplay = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.borderless)
            }
            .padding(14)
            Divider().opacity(0.4)
            Group {
                switch tab {
                case .web: GlanceLauncherWeb(add: add)
                case .widgets: GlanceLauncherWidgets(board: board, add: add)
                case .apps: GlanceLauncherApps(add: add)
                case .files: GlanceLauncherFiles(add: add)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
    }

    /// Adds a panel (set up by `configure`) and closes the launcher.
    private func add(_ kind: GlancePanelKind, _ title: String?, _ configure: @escaping (inout GlancePanel) -> Void) {
        glance.updateBoard(boardID) { board in
            if kind.isBuiltIn, let existing = board.panels.first(where: { $0.kind == kind }) {
                return GlancePolicy.setting(existing.id, shown: true, on: board)
            }
            var board = GlancePolicy.adding(kind, title: title, to: board)
            if let index = board.panels.indices.last { configure(&board.panels[index]) }
            return board
        }
        glance.launcherDisplay = nil
    }
}

typealias GlanceAdd = (GlancePanelKind, String?, @escaping (inout GlancePanel) -> Void) -> Void

// MARK: - Web

private struct GlanceLauncherWeb: View {
    let add: GlanceAdd
    @State private var address = ""
    @State private var phoneLayout = false

    private static let suggestions: [(name: String, address: String)] = [
        ("Gmail", "mail.google.com"), ("Google Calendar", "calendar.google.com"), ("X", "x.com"),
        ("YouTube", "youtube.com"), ("GitHub", "github.com/notifications"), ("Notion", "notion.so"),
        ("ChatGPT", "chatgpt.com"), ("Claude", "claude.ai"), ("Linear", "linear.app"), ("Cricbuzz", "cricbuzz.com"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A web page, kept loaded so it's there the moment you glance. It keeps its own sign-in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Address, like mail.google.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTyped)
                Button("Add", action: addTyped)
                    .buttonStyle(.borderedProminent)
                    .disabled(GlancePolicy.webURL(address) == nil)
            }
            Toggle("Phone layout (fits small panels)", isOn: $phoneLayout)
            Text("Popular").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Self.suggestions, id: \.address) { site in
                    Button {
                        addSite(name: site.name, address: site.address)
                    } label: {
                        Label(site.name, systemImage: "globe")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func addTyped() {
        guard let url = GlancePolicy.webURL(address) else { return }
        addSite(name: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web page", address: address)
    }

    private func addSite(name: String, address: String) {
        let mobile = phoneLayout
        add(.web, name) { panel in
            panel.address = address
            panel.mobileLayout = mobile
        }
    }
}

// MARK: - Widgets

private struct GlanceLauncherWidgets: View {
    let board: GlanceBoard?
    let add: GlanceAdd
    @State private var city = ""
    @State private var askingCity = false
    @State private var agentWidgets: [URL] = []

    private static let kinds: [GlancePanelKind] = [.calendar, .reminders, .clocks, .weather, .stocks, .nowPlaying,
                                                   .promises, .setups, .stash, .whatsapp]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(Self.kinds, id: \.self) { kind in
                        let onBoard = kind.isBuiltIn && (board?.panels.contains { $0.kind == kind && $0.isShown } ?? false)
                        Button {
                            if kind == .weather { askingCity = true } else { add(kind, nil) { _ in } }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: kind.symbol).font(.system(size: 22))
                                Text(kind.defaultTitle).font(.system(size: 12, weight: .medium))
                                if onBoard { Text("On the board").font(.system(size: 10)).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 74)
                            .background(Color.white.opacity(onBoard ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(onBoard)
                    }
                }
                if askingCity {
                    HStack {
                        TextField("City, like Pune or London", text: $city)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addWeather)
                        Button("Add Weather", action: addWeather)
                            .buttonStyle(.borderedProminent)
                            .disabled(city.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Divider().opacity(0.4)
                HStack {
                    Text("Agent widgets").font(.headline)
                    Spacer()
                    Button("Open Folder") {
                        NSWorkspace.shared.open(GlanceWebPanels.agentWidgetsFolder)
                    }
                }
                Text("Ask Claude Code, Codex or any agent to write an HTML widget into ~/Library/Application Support/NotchFlow/\(GlancePolicy.agentWidgetsFolder) (a build status, a dashboard, anything). It shows up here, and updates on the board when the agent changes the file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(agentWidgets, id: \.self) { file in
                    Button {
                        add(.html, file.deletingPathExtension().lastPathComponent) { $0.address = file.path }
                    } label: {
                        Label(file.deletingPathExtension().lastPathComponent, systemImage: GlancePanelKind.html.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .onAppear { agentWidgets = GlanceWebPanels.agentWidgets() }
    }

    private func addWeather() {
        let name = city.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        add(.weather, name) { $0.address = name }
    }
}

// MARK: - Apps

private struct GlanceLauncherApps: View {
    let add: GlanceAdd
    @State private var allowed = CGPreflightScreenCaptureAccess()
    @State private var choices: [GlanceLiveWindows.Choice] = []
    @State private var selectedApp: String?
    @State private var thumbnails: [String: NSImage] = [:]

    private struct App: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
    }

    private var apps: [App] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own }
            .compactMap { app -> App? in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return App(id: id, name: app.localizedName ?? id, icon: app.icon ?? NSImage())
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !allowed {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "record.circle").foregroundStyle(.orange).font(.title3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Allow Screen Recording to show app windows").font(.headline)
                        Text("Glance shows an app's window live only while the board is open. Nothing is saved or sent. After allowing it, quit and reopen NotchFlow if macOS asks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Allow…") {
                                _ = CGRequestScreenCaptureAccess()
                                allowed = CGPreflightScreenCaptureAccess()
                            }
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if let selectedApp, let app = apps.first(where: { $0.id == selectedApp }) {
                windowsOf(app)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 14) {
                        ForEach(apps) { app in
                            Button {
                                selectedApp = app.id
                            } label: {
                                VStack(spacing: 6) {
                                    Image(nsImage: app.icon).resizable().frame(width: 44, height: 44)
                                    Text(app.name).font(.system(size: 11)).lineLimit(1)
                                }
                                .frame(width: 92)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .task { await loadChoices() }
    }

    private func windowsOf(_ app: App) -> some View {
        let windows = choices.filter { $0.bundleID == app.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    selectedApp = nil
                } label: {
                    Label("All apps", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                Text(app.name).font(.headline)
            }
            if windows.isEmpty {
                Text(allowed ? "\(app.name) has no window open right now. Add it anyway, and its main window shows whenever it's open."
                     : "Allow Screen Recording above to see \(app.name)'s windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add \(app.name)") {
                    add(.window, app.name) { $0.windowApp = app.id }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(windows) { choice in
                            Button {
                                add(.window, app.name) { panel in
                                    panel.windowApp = choice.bundleID
                                    panel.windowTitle = choice.title
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Group {
                                        if let image = thumbnails[choice.id] {
                                            Image(nsImage: image).resizable().scaledToFit()
                                        } else {
                                            Image(systemName: "macwindow").font(.system(size: 30)).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 160, height: 100)
                                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                                    Text(choice.title.isEmpty ? app.name : choice.title)
                                        .font(.system(size: 11)).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .task {
                                if thumbnails[choice.id] == nil, let image = await GlanceLiveWindows.shared.thumbnail(for: choice) {
                                    thumbnails[choice.id] = image
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadChoices() async {
        allowed = CGPreflightScreenCaptureAccess()
        choices = await GlanceLiveWindows.shared.choices()
    }
}

// MARK: - Files

private struct GlanceLauncherFiles: View {
    let add: GlanceAdd

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A PDF (opens on the page you left it on) or an HTML file (a widget of your own).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose a PDF or HTML File…") { choose() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(16)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .html]
        panel.allowsMultipleSelection = false
        // Above the board.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let kind: GlancePanelKind = url.pathExtension.lowercased() == "pdf" ? .pdf : .html
        add(kind, url.deletingPathExtension().lastPathComponent) { $0.address = url.path }
    }
}
