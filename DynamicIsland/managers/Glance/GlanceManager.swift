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

    private var window: GlanceWindow?
    private var pressedAt: Date?
    private var previousApp: NSRunningApplication?
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        var boards = GlancePolicy.decodeBoards(Defaults[.glanceBoards])
        if boards.isEmpty { boards = [GlancePolicy.starterBoard()] }
        self.boards = boards
        activeBoardID = boards.first { $0.id.uuidString == Defaults[.glanceActiveBoard] }?.id ?? boards[0].id
    }

    var activeBoard: GlanceBoard {
        boards.first { $0.id == activeBoardID } ?? boards[0]
    }

    func start() {
        guard !started else { return }
        started = true
        // Called on the main thread.
        KeyboardShortcuts.onKeyDown(for: .glanceHold) { [weak self] in MainActor.assumeIsolated { self?.shortcutDown() } }
        KeyboardShortcuts.onKeyUp(for: .glanceHold) { [weak self] in MainActor.assumeIsolated { self?.shortcutUp() } }
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
                GlanceWebPanels.shared.preload(self.activeBoard)
            }
        }
    }

    // MARK: Hold or tap

    private func shortcutDown() {
        guard Defaults[.enableGlance] else { return }
        if isShowing {
            // Open (tapped earlier): the shortcut again closes it.
            if isPinned { hide() }
            return
        }
        pressedAt = Date()
        show(pinned: false)
    }

    private func shortcutUp() {
        guard let pressedAt else { return }
        self.pressedAt = nil
        if GlancePolicy.isTap(heldFor: Date().timeIntervalSince(pressedAt)) {
            pin()
        } else {
            hide()
        }
    }

    // MARK: Showing

    /// Shows the board on the screen with the pointer.
    func show(pinned: Bool) {
        guard !isShowing else {
            if pinned { pin() }
            return
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        GlanceWebPanels.shared.prepare(activeBoard)

        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        isShowing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
        if pinned { pin() }
    }

    /// Keeps the board open (and takes the keyboard, so Esc closes it and you can type in a page).
    func pin() {
        guard isShowing, let window else { return }
        isPinned = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard isShowing, let window else { return }
        let wasPinned = isPinned
        isShowing = false
        isPinned = false
        pressedAt = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                guard !GlanceManager.shared.isShowing else { return }
                window.orderOut(nil)
            }
        })
        if wasPinned, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
        if Defaults[.glanceUnloadOnBattery], EnergySaver.shared.conditions.onBattery {
            GlanceWebPanels.shared.unloadAll()
        }
    }

    private func makeWindow() -> GlanceWindow {
        let window = GlanceWindow()
        window.onEscape = { [weak self] in self?.hide() }
        window.contentView = NSHostingView(rootView: GlanceBoardView())
        return window
    }

    // MARK: Boards

    func selectBoard(_ id: UUID) {
        guard boards.contains(where: { $0.id == id }) else { return }
        activeBoardID = id
        Defaults[.glanceActiveBoard] = id.uuidString
        if isShowing { GlanceWebPanels.shared.prepare(activeBoard) }
    }

    /// Changes the board on screen (and in Settings).
    func updateActive(_ change: (GlanceBoard) -> GlanceBoard) {
        guard let index = boards.firstIndex(where: { $0.id == activeBoardID }) else { return }
        boards[index] = change(boards[index])
        persist()
        if isShowing { GlanceWebPanels.shared.prepare(activeBoard) }
    }

    func updatePanel(_ id: UUID, _ change: (inout GlancePanel) -> Void) {
        updateActive { board in
            var board = board
            if let index = board.panels.firstIndex(where: { $0.id == id }) { change(&board.panels[index]) }
            return board
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
        boards.removeAll { $0.id == activeBoardID }
        selectBoard(boards[0].id)
        persist()
    }

    private func persist() {
        Defaults[.glanceBoards] = GlancePolicy.encodeBoards(boards)
    }
}

/// The full-screen window the board is drawn in: above everything, on every
/// desktop and over full-screen apps, without taking focus until it's kept open.
final class GlanceWindow: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
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
