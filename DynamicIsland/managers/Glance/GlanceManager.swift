// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

extension Defaults.Keys {
    /// Glance: hold a shortcut to see a board of panels over everything.
    static let enableGlance = Key<Bool>("enableGlance", default: true)
    /// Your boards (layouts), as JSON.
    static let glanceBoards = Key<Data>("glanceBoards", default: Data())
    static let glanceActiveBoard = Key<String>("glanceActiveBoard", default: "")
    /// Web panels don't load ad hosts and hide cookie banners.
    static let glanceHideAds = Key<Bool>("glanceHideAds", default: true)
    /// On battery, web panels are unloaded when the board closes (they load again next time).
    static let glanceUnloadOnBattery = Key<Bool>("glanceUnloadOnBattery", default: true)
    /// The page each PDF panel was left on, by panel id.
    static let glancePDFPages = Key<[String: Int]>("glancePDFPages", default: [:])
    /// The board each display shows, by display id (a display without one shows the selected board when the pointer is on it).
    static let glanceDisplayBoards = Key<[String: String]>("glanceDisplayBoards", default: [:])
    /// "holdOrTap" (hold to peek, tap to keep open), "hold" or "toggle".
    static let glanceMode = Key<String>("glanceMode", default: "holdOrTap")
    /// What opens it: "shortcut", or a modifier key on its own ("fn", "shift", "rightCommand"…).
    static let glanceTrigger = Key<String>("glanceTrigger", default: "shortcut")
    /// Every display shows the selected board (instead of a board per display).
    static let glanceSameOnAllDisplays = Key<Bool>("glanceSameOnAllDisplays", default: false)
    /// Where web pages open: "auto" (your browser, Chrome Beta first), a browser's bundle id, or "builtIn".
    static let glanceBrowser = Key<String>("glanceBrowser", default: "auto")
    /// App window panels as live pictures (screen recording) instead of the real window.
    static let glanceLivePicture = Key<Bool>("glanceLivePicture", default: false)
    /// The screen behind the panels: "clear", "dim" or "blur".
    static let glanceBackdrop = Key<String>("glanceBackdrop", default: "dim")
}

/// Glance: hold the shortcut and a board of your panels (web pages, PDFs,
/// today's calendar, reminders, clocks, promises, setups…) covers the
/// screen, over full-screen apps too; let go and it's gone. A tap keeps it
/// open until Esc, a click outside the panels, or the shortcut again.
@MainActor
final class GlanceManager: ObservableObject {
    static let shared = GlanceManager()

    @Published private(set) var boards: [GlanceBoard]
    @Published private(set) var activeBoardID: UUID
    @Published private(set) var isShowing = false
    @Published private(set) var isPinned = false
    /// While showing: the board on each display.
    @Published private(set) var shownBoards: [String: UUID] = [:]
    /// The board you gave each display (Settings › Glance › Displays).
    @Published private(set) var displayBoards: [String: UUID] = [:]
    /// Arranging the boards on screen (Edit on the board).
    @Published private(set) var isEditing = false
    /// The display showing the + launcher (adding a panel).
    @Published var launcherDisplay: String?
    /// A real app window was moved into its panel to be used there.
    private var isInteracting = false
    /// A click on the board kept it open (the release of the key that's held doesn't close it).
    private var keptOpenByClick = false

    private var windows: [String: GlanceWindow] = [:]
    private var pointerDisplay: String?
    private var gesture = GlancePolicy.ModifierGesture(mode: .hold)
    private var holdCheck: DispatchWorkItem?
    private var releaseWatch: Timer?
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        var boards = GlancePolicy.decodeBoards(Defaults[.glanceBoards])
        if boards.isEmpty { boards = [GlancePolicy.starterBoard()] }
        self.boards = boards
        activeBoardID = boards.first { $0.id.uuidString == Defaults[.glanceActiveBoard] }?.id ?? boards[0].id
        displayBoards = Defaults[.glanceDisplayBoards].compactMapValues(UUID.init(uuidString:))
    }

    var activeBoard: GlanceBoard {
        boards.first { $0.id == activeBoardID } ?? boards[0]
    }

    /// The board shown on a display right now (nil: that display shows none
    /// this time, so its window draws nothing and keeps no web page or window).
    func board(onDisplay key: String) -> GlanceBoard? {
        guard let id = shownBoards[key] else { return nil }
        return boards.first { $0.id == id }
    }

    /// The boards on screen (or about to be).
    var boardsOnScreen: [GlanceBoard] {
        let ids = Set(shownBoards.values)
        return ids.isEmpty ? [activeBoard] : boards.filter { ids.contains($0.id) }
    }

    // MARK: Displays

    /// A display's lasting id (stays the same across restarts and reconnecting).
    static func key(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        let id = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), let text = CFUUIDCreateString(nil, uuid) {
            return text as String
        }
        return String(id)
    }

    /// Gives a display its own board (nil: the selected board, when the pointer is on it).
    func setBoard(_ id: UUID?, forDisplay key: String) {
        displayBoards[key] = id
        Defaults[.glanceDisplayBoards] = displayBoards.mapValues(\.uuidString)
    }

    /// Switching boards on the board itself: with one display, the selected
    /// board changes; with several, that display's board does.
    func switchBoard(_ id: UUID, onDisplay key: String) {
        if NSScreen.screens.count > 1 { setBoard(id, forDisplay: key) } else { selectBoard(id) }
        if isShowing {
            shownBoards[key] = id
            prepareContent()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        // Called on the main thread.
        KeyboardShortcuts.onKeyDown(for: .glanceHold) { [weak self] in MainActor.assumeIsolated { self?.shortcutDown() } }
        KeyboardShortcuts.onKeyUp(for: .glanceHold) { [weak self] in MainActor.assumeIsolated { self?.shortcutUp() } }
        installModifierMonitors()
        Defaults.publisher(.enableGlance, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    if !change.newValue { self?.hide() }
                }
            }
            .store(in: &cancellables)
        // Web pages load in the background now, so the first glance is instant.
        if Defaults[.enableGlance] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self else { return }
                GlanceWebPanels.shared.prepare([self.activeBoard] + self.boards.filter { Set(self.displayBoards.values).contains($0.id) })
            }
        }
    }

    // MARK: Opening it

    private var mode: GlancePolicy.Mode { GlancePolicy.Mode(rawValue: Defaults[.glanceMode]) ?? .holdOrTap }
    private var trigger: GlancePolicy.Trigger { GlancePolicy.Trigger(rawValue: Defaults[.glanceTrigger]) ?? .shortcut }
    /// The shortcut went down while the board was kept open: that press closed it, its release does nothing.
    private var shortcutClosedIt = false

    private func shortcutDown() {
        guard Defaults[.enableGlance], trigger == .shortcut, !isRecordingKey else { return }
        shortcutClosedIt = false
        switch mode {
        case .hold, .holdOrTap:
            if isShowing {
                if isPinned { hide(); shortcutClosedIt = true }
                return
            }
            gesture.mode = mode
            gesture.triggerDown(at: Date())
            show(pinned: false)
            watchShortcutRelease()
        case .toggle:
            if isShowing { hide() } else { show(pinned: true) }
        }
    }

    private func shortcutUp() {
        guard trigger == .shortcut, mode != .toggle else { return }
        if shortcutClosedIt {
            shortcutClosedIt = false
            return
        }
        guard isShowing, !isPinned else { return }
        apply(gesture.triggerUp(at: Date(), showing: isShowing))
    }

    /// In case the key-up of the shortcut is missed: letting go of its
    /// modifiers hides the board too.
    private func watchShortcutRelease() {
        releaseWatch?.invalidate()
        guard let needed = KeyboardShortcuts.getShortcut(for: .glanceHold)?.modifiers.intersection([.command, .option, .control, .shift]),
              !needed.isEmpty else { return }
        releaseWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            Task { @MainActor in
                let manager = GlanceManager.shared
                guard manager.isShowing, !manager.isPinned, manager.mode != .toggle, manager.gesture.downAt != nil else {
                    timer.invalidate()
                    return
                }
                if !NSEvent.modifierFlags.contains(needed) {
                    timer.invalidate()
                    manager.apply(manager.gesture.triggerUp(at: Date(), showing: manager.isShowing))
                }
            }
        }
    }

    /// A modifier key on its own (fn, Shift, right Command…): watched
    /// everywhere (Accessibility lets NotchFlow see key presses) to tell a
    /// hold or a tap from typing.
    private func installModifierMonitors() {
        let handle: (NSEvent) -> Void = { event in
            MainActor.assumeIsolated { GlanceManager.shared.handle(event) }
        }
        let types: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: types, handler: handle) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: types, handler: { event in
            handle(event)
            return event
        }) { monitors.append(local) }
    }

    private func handle(_ event: NSEvent) {
        // Esc closes the board from anywhere.
        if event.type == .keyDown, event.keyCode == 53, isShowing {
            hide()
            return
        }
        if isRecordingKey {
            recordKey(event)
            return
        }
        // Clicking a panel (or a real window on the board) while peeking keeps the board open, to use it.
        if event.type == .leftMouseDown, isShowing, !isPinned, mode == .holdOrTap {
            let onBoard = event.window is GlanceWindow
            if onBoard || GlanceRealWindows.shared.contains(screenPoint: NSEvent.mouseLocation) {
                isPinned = true
                keptOpenByClick = true
            }
        }
        let trigger = self.trigger
        guard Defaults[.enableGlance], trigger != .shortcut else { return }
        gesture.mode = mode
        switch event.type {
        case .flagsChanged where trigger.keyCodes.contains(event.keyCode):
            if GlancePolicy.isModifierDown(keyCode: event.keyCode, flags: event.modifierFlags.rawValue) {
                gesture.triggerDown(at: Date(), pinned: isShowing && isPinned)
                holdCheck?.cancel()
                let check = DispatchWorkItem {
                    MainActor.assumeIsolated {
                        let manager = GlanceManager.shared
                        manager.apply(manager.gesture.holdElapsed(at: Date(), showing: manager.isShowing))
                    }
                }
                holdCheck = check
                DispatchQueue.main.asyncAfter(deadline: .now() + GlancePolicy.ModifierGesture.holdDelay + 0.02, execute: check)
            } else {
                holdCheck?.cancel()
                let action = gesture.triggerUp(at: Date(), showing: isShowing)
                if keptOpenByClick {
                    // This hold's release: you clicked to use the board, it stays.
                    keptOpenByClick = false
                    if action == .hide { return }
                }
                apply(action)
            }
        default:
            // Another key, another modifier or a click while the trigger is down.
            gesture.otherInput(showing: isShowing)
        }
    }

    private func apply(_ action: GlancePolicy.ModifierGesture.Action) {
        switch action {
        case .none: break
        case .show: show(pinned: false)
        case .hide: hide()
        case .toggle: if isShowing { hide() } else { show(pinned: true) }
        case .pin: if isShowing { pin() } else { show(pinned: true) }
        }
    }

    // MARK: Recording the key

    /// Settings › Glance › Record: the next key pressed becomes what opens
    /// Glance: a modifier on its own (Left Shift, fn, Right Command…) or a
    /// key with modifiers (a shortcut).
    @Published private(set) var isRecordingKey = false
    private var recordingModifier: UInt16?

    func startRecordingKey() {
        isRecordingKey = true
        recordingModifier = nil
    }

    func cancelRecordingKey() {
        isRecordingKey = false
        recordingModifier = nil
    }

    private func recordKey(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            if GlancePolicy.isModifierDown(keyCode: event.keyCode, flags: event.modifierFlags.rawValue) {
                recordingModifier = event.keyCode
            } else if recordingModifier == event.keyCode, let trigger = GlancePolicy.Trigger.forKeyCode(event.keyCode) {
                // Pressed and released on its own.
                Defaults[.glanceTrigger] = trigger.rawValue
                cancelRecordingKey()
            }
        case .keyDown:
            if event.keyCode == 53 {
                cancelRecordingKey()
                return
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty || (122...135).contains(Int(event.keyCode)) || [105, 107, 113, 106, 64, 79, 80, 90].contains(Int(event.keyCode)),
                  let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
                // A plain letter would open Glance while typing; wait for a key with modifiers.
                recordingModifier = nil
                return
            }
            KeyboardShortcuts.setShortcut(shortcut, for: .glanceHold)
            Defaults[.glanceTrigger] = GlancePolicy.Trigger.shortcut.rawValue
            cancelRecordingKey()
        default:
            break
        }
    }

    // MARK: Showing

    /// Shows the boards: the display with the pointer, and every other
    /// display you gave a board of its own.
    func show(pinned: Bool) {
        guard !isShowing else {
            if pinned { pin() }
            return
        }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let pointerScreen = screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens[0]
        let keys = screens.map(Self.key(for:))
        pointerDisplay = Self.key(for: pointerScreen)
        shownBoards = GlancePolicy.boardsToShow(displays: keys, pointer: pointerDisplay, assignments: displayBoards,
                                                selected: activeBoardID, boards: Set(boards.map(\.id)),
                                                sameOnAll: Defaults[.glanceSameOnAllDisplays])
        previousApp = NSWorkspace.shared.frontmostApplication
        prepareContent()

        for (screen, key) in zip(screens, keys) {
            guard shownBoards[key] != nil else {
                windows[key]?.orderOut(nil)
                continue
            }
            let window = windows[key] ?? makeWindow(displayKey: key)
            windows[key] = window
            window.setFrame(screen.frame, display: false)
            window.level = GlanceWindow.boardLevel
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                window.animator().alphaValue = 1
            }
        }
        // Windows of displays that were unplugged.
        for key in windows.keys where !keys.contains(key) { windows[key] = nil }
        isShowing = true
        presentRealWindows()
        GlanceLiveWindows.shared.resume()
        GlanceStocks.shared.startRefreshing(GlanceManager.shared.boardsOnScreen)
        GlanceWeather.shared.refresh(boardsOnScreen)
        if pinned { pin() }
    }

    /// Which copy of a panel's page or window a display shows: the panel's
    /// own, or (with the same board on several displays) one per display.
    func instanceKey(_ panel: GlancePanel, display: String) -> String {
        guard Defaults[.glanceSameOnAllDisplays], !display.isEmpty, display != pointerDisplay else { return panel.id.uuidString }
        return panel.id.uuidString + "|" + display
    }

    /// Real windows (your browser's pages, apps' own windows) move into their
    /// spots and come above the board, which steps down to the normal window
    /// level so they can.
    private func presentRealWindows() {
        let screens = NSScreen.screens
        var layout: [(board: GlanceBoard, screen: NSScreen)] = []
        for screen in screens {
            let key = Self.key(for: screen)
            guard let board = board(onDisplay: key) else { continue }
            layout.append((board, screen))
        }
        let hasReal = layout.contains { $0.board.panels.contains { $0.isShown && GlanceRealWindows.usesRealWindow($0) } }
        guard hasReal else { return }
        for window in windows.values { window.level = .normal }
        GlanceRealWindows.shared.present(layout)
    }

    /// Loads what the boards on screen show (web pages).
    private func prepareContent() {
        GlanceWebPanels.shared.prepare(boardsOnScreen)
    }

    /// Keeps the board open (and takes the keyboard, so Esc closes it and you can type in a page).
    func pin() {
        guard isShowing, let window = pointerDisplay.flatMap({ windows[$0] }) ?? windows.values.first else { return }
        isPinned = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard isShowing else { return }
        let wasPinned = isPinned
        isShowing = false
        isPinned = false
        isEditing = false
        launcherDisplay = nil
        keptOpenByClick = false
        if isInteracting {
            isInteracting = false
            GlanceLiveWindows.shared.restoreMoved()
        }
        let hadRealWindows = GlanceRealWindows.shared.isPresenting
        GlanceRealWindows.shared.dismiss()
        if hadRealWindows, !wasPinned, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            // Real windows were brought forward; you go back to the app you were in.
            previousApp.activate()
        }
        releaseWatch?.invalidate()
        releaseWatch = nil
        GlanceLiveWindows.shared.pauseAll()
        GlanceStocks.shared.stopRefreshing()
        for window in windows.values where window.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                window.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    guard !GlanceManager.shared.isShowing else { return }
                    window.orderOut(nil)
                }
            })
        }
        if wasPinned, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
        if Defaults[.glanceUnloadOnBattery], EnergySaver.shared.conditions.onBattery {
            GlanceWebPanels.shared.unloadAll()
        }
    }

    private func makeWindow(displayKey: String) -> GlanceWindow {
        let window = GlanceWindow()
        window.onEscape = { [weak self] in self?.hide() }
        window.contentView = NSHostingView(rootView: GlanceBoardView(displayKey: displayKey))
        return window
    }

    // MARK: Boards

    func selectBoard(_ id: UUID) {
        guard boards.contains(where: { $0.id == id }) else { return }
        activeBoardID = id
        Defaults[.glanceActiveBoard] = id.uuidString
        if isShowing { prepareContent() }
    }

    /// Changes the board on screen (and in Settings).
    func updateActive(_ change: (GlanceBoard) -> GlanceBoard) {
        guard let index = boards.firstIndex(where: { $0.id == activeBoardID }) else { return }
        boards[index] = change(boards[index])
        persist()
        if isShowing {
            prepareContent()
            GlanceStocks.shared.startRefreshing(boardsOnScreen)
        }
    }

    /// Changes a panel, on whichever board it's on.
    func updatePanel(_ id: UUID, _ change: (inout GlancePanel) -> Void) {
        guard let boardIndex = boards.firstIndex(where: { $0.panels.contains { $0.id == id } }),
              let index = boards[boardIndex].panels.firstIndex(where: { $0.id == id }) else { return }
        change(&boards[boardIndex].panels[index])
        persist()
        if isShowing { prepareContent() }
    }

    /// Changes any board (the one on a display, while arranging it there).
    func updateBoard(_ id: UUID, _ change: (GlanceBoard) -> GlanceBoard) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index] = change(boards[index])
        persist()
        if isShowing {
            prepareContent()
            GlanceStocks.shared.startRefreshing(boardsOnScreen)
            GlanceWeather.shared.refresh(boardsOnScreen)
            GlanceLiveWindows.shared.resume()
        }
    }

    // MARK: Editing on the board

    /// Arrange the boards where they are: the board stays open and takes the keyboard.
    func startEditing() {
        if !isShowing { show(pinned: true) } else { pin() }
        isEditing = true
        // Real windows step aside so the panels can be arranged.
        GlanceRealWindows.shared.stepAside()
        for window in windows.values { window.level = GlanceWindow.boardLevel }
    }

    func stopEditing() {
        isEditing = false
        launcherDisplay = nil
        presentRealWindows()
    }

    /// The cell of a board under the pointer, on a display (for placing a new panel there).
    func pointerCell(onDisplay key: String) -> (x: Int, y: Int)? {
        guard let screen = NSScreen.screens.first(where: { Self.key(for: $0) == key }) else { return nil }
        let pointer = NSEvent.mouseLocation
        guard screen.frame.contains(pointer) else { return nil }
        let area = GlanceLayout.boardArea(screen.frame.size)
        let local = CGPoint(x: pointer.x - screen.frame.minX, y: screen.frame.maxY - pointer.y)
        return GlancePolicy.cell(atFractionX: Double((local.x - area.minX) / area.width), y: Double((local.y - area.minY) / area.height))
    }

    /// Clicking an App window panel: the real window moves into the panel,
    /// above the board, to be used right there; it goes back when Glance
    /// closes. If it can't be moved, Glance closes and the window comes forward.
    func interact(with panel: GlancePanel, display: String) {
        guard let screen = NSScreen.screens.first(where: { Self.key(for: $0) == display }) ?? NSScreen.main else { return }
        let area = GlanceLayout.boardArea(screen.frame.size)
        let rect = GlanceLayout.rect(for: panel.frame, in: area, gap: GlanceLayout.gap)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let target = CGRect(x: screen.frame.minX + rect.minX, y: primaryHeight - screen.frame.maxY + rect.minY,
                            width: rect.width, height: rect.height)
        if GlanceLiveWindows.shared.moveIntoPanel(panel, frame: target) {
            isInteracting = true
            // Let the app's window sit above the board.
            for window in windows.values { window.level = .normal }
        } else {
            hide()
            GlanceLiveWindows.shared.bringForward(panel)
        }
    }

    /// Opens what a panel shows in its own app (right-click › Open in App).
    func openInApp(_ panel: GlancePanel) {
        let workspace = NSWorkspace.shared
        func open(bundle: String) {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundle) {
                workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
        hide()
        switch panel.kind {
        case .web:
            if let url = GlancePolicy.webURL(panel.address) { workspace.open(url) }
        case .pdf, .html:
            workspace.open(URL(fileURLWithPath: (panel.address as NSString).expandingTildeInPath))
        case .window:
            GlanceLiveWindows.shared.bringForward(panel)
        case .calendar: open(bundle: "com.apple.iCal")
        case .reminders: open(bundle: "com.apple.reminders")
        case .clocks: open(bundle: "com.apple.clock")
        case .stocks: open(bundle: "com.apple.stocks")
        case .weather: open(bundle: "com.apple.weather")
        case .nowPlaying:
            if let bundle = MusicManager.shared.bundleIdentifier { open(bundle: bundle) }
        case .whatsapp: open(bundle: "net.whatsapp.WhatsApp")
        case .promises, .setups, .stash:
            SettingsWindowController.shared.showWindow()
        }
    }

    /// Whether a panel has an app to open it in.
    static func canOpenInApp(_ panel: GlancePanel) -> Bool {
        switch panel.kind {
        case .web: return GlancePolicy.webURL(panel.address) != nil
        case .pdf, .html: return !panel.address.isEmpty
        case .window: return !panel.windowApp.isEmpty
        default: return true
        }
    }

    func newBoard() {
        var board = GlanceBoard(name: "Layout \(boards.count + 1)")
        board = GlancePolicy.adding(.calendar, to: board)
        boards.append(board)
        selectBoard(board.id)
        persist()
    }

    func duplicateActive() {
        let copy = GlancePolicy.duplicate(activeBoard, name: activeBoard.name + " copy")
        boards.append(copy)
        selectBoard(copy.id)
        persist()
    }

    func renameActive(_ name: String) {
        updateActive { board in
            var board = board
            board.name = name
            return board
        }
    }

    func deleteActive() {
        guard boards.count > 1 else { return }
        let removed = activeBoardID
        boards.removeAll { $0.id == removed }
        for (key, id) in displayBoards where id == removed { setBoard(nil, forDisplay: key) }
        selectBoard(boards[0].id)
        persist()
    }

    private func persist() {
        Defaults[.glanceBoards] = GlancePolicy.encodeBoards(boards)
        GlanceRealWindows.shared.keepOnly(Set(boards.flatMap(\.panels).filter { $0.kind == .web }.map(\.id)))
    }
}

/// The full-screen window the board is drawn in: above everything, on every
/// desktop and over full-screen apps, without taking focus until it's kept open.
final class GlanceWindow: NSPanel {
    var onEscape: (() -> Void)?
    /// Above every app's windows and the menu bar.
    static let boardLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)

    init() {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.boardLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
