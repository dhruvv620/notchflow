/*
 * NotchFlow
 * Copyright (C) 2026 dhruvv620
 * Portions Copyright (C) 2024-2026 Atoll Contributors
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

import Defaults
import SwiftUI

/// Click to make the open tab bigger (Regular, Large, Extra large, then back);
/// hold for the list.
private struct TabSizeButton: View {
    let view: NotchViews
    @Default(.notchTabSizes) private var sizes
    @Default(.agentPanelSize) private var agentSize
    @Default(.cuelyPanelSize) private var cuelySize

    private var current: NotchTabSize {
        _ = (sizes, agentSize, cuelySize)  // redraw when any of them changes
        return NotchTabSizing.size(for: view)
    }

    var body: some View {
        Menu {
            ForEach(NotchTabSize.allCases, id: \.rawValue) { size in
                Button {
                    applyNotchLayoutChange { NotchTabSizing.setSize(size, for: view) }
                } label: {
                    if size == current { Label(size.title, systemImage: "checkmark") } else { Text(size.title) }
                }
            }
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.055))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: current == .extraLarge
                          ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .foregroundColor(.white)
                        .imageScale(.small)
                }
        } primaryAction: {
            applyNotchLayoutChange { NotchTabSizing.setSize(current.next, for: view) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tab size: \(current.title). Click for bigger, hold for sizes.")
    }
}

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @State private var showColorPickerPopover = false
    @State private var showTimerPopover = false
    @State private var cameraPopoverToken = UUID()
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showColorPickerIcon) var showColorPickerIcon
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.showMinimalisticBatteryIndicator) var showMinimalisticBatteryIndicator
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showMirror) private var showMirror
    
    var body: some View {
        VStack(spacing: 0) {
            if !enableMinimalisticUI {
                Color.clear.frame(height: notchCameraClearance(for: vm.screen))
            }
            HStack(spacing: 6) {
            HStack {
                if !enableMinimalisticUI {
                    let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty
                    if shouldShowTabs {
                        TabSelectionView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(.vertical, 1)

            HStack(spacing: 4) {
                if vm.notchState == .open && !enableMinimalisticUI {
                    if showMirror {
                        Button(action: {
                            vm.toggleCameraPreview()
                        }) {
                            Capsule()
                                .fill(Color.white.opacity(0.055))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "web.camera")
                                        .foregroundColor(.white)
                                        .padding()
                                        .imageScale(.medium)
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Mirror")
                        .popover(isPresented: $vm.isCameraExpanded, arrowEdge: .bottom) {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Mirror").font(.headline)
                                    Spacer()
                                    Button { vm.isCameraExpanded = false } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Close mirror")
                                }
                                CameraPreviewView(webcamManager: webcamManager)
                                    .frame(width: 220, height: 220)
                                    .environmentObject(vm)
                            }
                            .padding(12)
                            .frame(width: 244)
                        }
                    }
                    
                    // Focus: nothing in the notch disturbs you until you click again.
                    FocusSessionButton()
                    
                    // ColorPicker button
                    if Defaults[.enableColorPickerFeature] && showColorPickerIcon{
                        Button(action: {
                            switch Defaults[.colorPickerDisplayMode] {
                            case .panel:
                                ColorPickerPanelManager.shared.toggleColorPickerPanel()
                            case .popover:
                                showColorPickerPopover.toggle()
                            }
                        }) {
                            Capsule()
                                .fill(Color.white.opacity(0.055))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "eyedropper")
                                        .foregroundColor(.white)
                                        .padding()
                                        .imageScale(.medium)
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showColorPickerPopover, arrowEdge: .bottom) {
                            ColorPickerPopover()
                        }
                        .onChange(of: showColorPickerPopover) { isActive in
                            vm.isColorPickerPopoverActive = isActive
                            
                            // If popover was closed, trigger a hover recheck
                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }
                    
                    if Defaults[.enableTimerFeature] && timerDisplayMode == .popover {
                        Button(action: {
                            withAnimation(.smooth) {
                                showTimerPopover.toggle()
                            }
                        }) {
                            Capsule()
                                .fill(Color.white.opacity(0.055))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "timer")
                                        .foregroundColor(.white)
                                        .padding()
                                        .imageScale(.medium)
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showTimerPopover, arrowEdge: .bottom) {
                            TimerPopover()
                        }
                        .onChange(of: showTimerPopover) { isActive in
                            vm.isTimerPopoverActive = isActive
                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }
                    
                    // Make this tab bigger or smaller (remembered per tab).
                    if NotchTabSizing.isResizable(coordinator.currentView) {
                        TabSizeButton(view: coordinator.currentView)
                    }

                    if Defaults[.settingsIconInNotch] {
                        Button(action: {
                            SettingsWindowController.shared.showWindow()
                        }) {
                            Capsule()
                                .fill(Color.white.opacity(0.055))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "gear")
                                        .foregroundColor(.white)
                                        .padding()
                                        .imageScale(.medium)
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Screen Recording Indicator
                    if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && !shouldSuppressStatusIndicators {
                        RecordingIndicator()
                            .frame(width: 30, height: 30) // Same size as other header elements
                    }

                    if Defaults[.enableDoNotDisturbDetection]
                        && Defaults[.showDoNotDisturbIndicator]
                        && doNotDisturbManager.isDoNotDisturbActive
                        && !shouldSuppressStatusIndicators {
                        FocusIndicator()
                            .frame(width: 30, height: 30)
                            .transition(.opacity)
                    }
                }

                if vm.notchState == .open && showBatteryIndicator {
                    if enableMinimalisticUI {
                        // In minimalistic notch mode, show the battery pill only when
                        // showMinimalisticBatteryIndicator is enabled (and not DI mode).
                        if !shouldUseDynamicIslandMode(for: vm.screen) && showMinimalisticBatteryIndicator {
                            MinimalisticBatteryView(
                                levelBattery: batteryModel.levelBattery,
                                isPluggedIn: batteryModel.isPluggedIn,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                bodyWidth: 28,
                                bodyHeight: 14,
                                isForNotification: false,
                                showPercentInside: showBatteryPercentInside
                            )
                            .padding(.trailing, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    } else {
                        DynamicIslandBatteryView(
                            batteryWidth: 30,
                            isCharging: batteryModel.isCharging,
                            isInLowPowerMode: batteryModel.isInLowPowerMode,
                            isPluggedIn: batteryModel.isPluggedIn,
                            levelBattery: batteryModel.levelBattery,
                            maxCapacity: batteryModel.maxCapacity,
                            timeToFullCharge: batteryModel.timeToFullCharge,
                            isForNotification: false
                        )
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: enableMinimalisticUI ? .infinity : nil, alignment: .trailing)
            .fixedSize(horizontal: !enableMinimalisticUI, vertical: false)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
            }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .onChange(of: vm.isCameraExpanded) { _, visible in
            vm.setAutoCloseSuppression(visible, token: cameraPopoverToken)
            if !visible {
                webcamManager.stopSession()
                vm.shouldRecheckHover.toggle()
            }
        }
        .onChange(of: vm.notchState) { _, state in
            if state == .closed { dismissCameraPreview() }
        }
        .onChange(of: showMirror) { _, enabled in
            if !enabled { dismissCameraPreview() }
        }
        .onDisappear { dismissCameraPreview() }
        .onChange(of: coordinator.shouldToggleClipboardPopover) { _ in
            // Only toggle if clipboard is enabled
            if Defaults[.enableClipboardManager] {
                switch clipboardDisplayMode {
                case .panel:
                    ClipboardPanelManager.shared.toggleClipboardPanel()
                case .popover, .separateTab:
                    if coordinator.currentView == .notes {
                        coordinator.currentView = .home
                    } else {
                        coordinator.currentView = .notes
                    }
                }
            }
        }
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }
}

private extension DynamicIslandHeader {
    func dismissCameraPreview() {
        guard vm.isCameraExpanded else {
            vm.setAutoCloseSuppression(false, token: cameraPopoverToken)
            return
        }
        vm.isCameraExpanded = false
        vm.setAutoCloseSuppression(false, token: cameraPopoverToken)
        webcamManager.stopSession()
    }

    var shouldSuppressStatusIndicators: Bool {
        Defaults[.settingsIconInNotch]
            && Defaults[.showColorPickerIcon]
            && Defaults[.enableTimerFeature]
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
