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

import Cocoa

class DynamicIslandWindow: NSPanel {
    private var inputController: NotchWindowInputController?
    private var inputRefreshScheduled = false

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        // Start pass-through until the visible surface publishes its native
        // input region; the hosting window may be much larger than that surface.
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isMovable = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .canJoinAllSpaces,
            .ignoresCycle,
            .stationary,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        ScreenCaptureVisibilityManager.shared.register(self, scope: .entireInterface)
    }
    
    func installInputRegion(_ probe: NotchInputRegionProbe) {
        if inputController == nil { inputController = NotchWindowInputController(window: self) }
        inputController?.install(probe)
    }
    func removeInputRegion(_ probe: NotchInputRegionProbe) { inputController?.remove(probe) }
    func refreshInputRegion() { inputController?.refresh() }
    func containsInteractivePoint(_ point: NSPoint) -> Bool { inputController?.contains(screenPoint: point) == true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        // AppKit may call this while laying out its hosting view. Keep native
        // event-property writes out of that window display/constraint cycle.
        // Probe state updates still clamp the collapsed region immediately.
        guard !inputRefreshScheduled else { return }
        inputRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputRefreshScheduled = false
            self.inputController?.refresh()
        }
    }

    override var alphaValue: CGFloat {
        didSet { inputController?.refresh() }
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        inputController?.resume()
    }
    override func orderOut(_ sender: Any?) {
        inputController?.suspend()
        super.orderOut(sender)
    }
    override func close() {
        inputController?.suspend()
        super.close()
    }

    override var canBecomeKey: Bool {
        true
    }
    
    override var canBecomeMain: Bool {
        true
    }

}
