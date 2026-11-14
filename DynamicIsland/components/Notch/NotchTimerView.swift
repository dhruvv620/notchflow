// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

private enum TimerSection: String, CaseIterable, Identifiable {
    case timer = "Timer", pomodoro = "Pomodoro", stopwatch = "Stopwatch"
    var id: String { rawValue }
}

/// Three compact tools share one tab; secondary duration controls open in a popover.
struct NotchTimerView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var modes = TimerModesManager.shared
    @Default(.enableTimerFeature) private var enabled
    @Default(.timerPresets) private var presets
    @AppStorage("notchflowTimerSection") private var storedSection = TimerSection.timer.rawValue
    @AppStorage("customTimerDuration") private var timerDuration: Double = 600
    @AppStorage("notchflowPomodoroFocusMinutes") private var focusMinutes: Double = 25
    @AppStorage("notchflowPomodoroShortBreakMinutes") private var shortBreakMinutes: Double = 5
    @AppStorage("notchflowPomodoroLongBreakMinutes") private var longBreakMinutes: Double = 15
    @AppStorage("notchflowPomodoroSessionCount") private var sessionsBeforeLongBreak: Int = 4
    @State private var showConfiguration = false
    @State private var replacingTimer = false
    @State private var pendingStart: TimerSection = .timer
    @State private var suppressionToken = UUID()

    private var section: TimerSection { TimerSection(rawValue: storedSection) ?? .timer }
    private var configuration: PomodoroConfiguration {
        PomodoroConfiguration(focusDuration: focusMinutes * 60, shortBreakDuration: shortBreakMinutes * 60,
                              longBreakDuration: longBreakMinutes * 60, sessionsBeforeLongBreak: sessionsBeforeLongBreak)
    }

    var body: some View {
        Group {
            if enabled {
                VStack(spacing: 4) {
                    header
                    navigation
                    Group {
                        switch section {
                        case .timer: countdownContent
                        case .pomodoro: pomodoroContent
                        case .stopwatch: stopwatchContent
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            } else {
                ContentUnavailableView("Timers are off", systemImage: "timer", description: Text("Enable Timer in Settings to use these tools."))
            }
        }
        .environment(\.colorScheme, .dark)
        .popover(isPresented: $showConfiguration, arrowEdge: .bottom) { configurationPopover }
        .confirmationDialog("Replace the timer shown in the notch?", isPresented: $replacingTimer) {
            Button("Replace timer") { begin(pendingStart) }
        } message: {
            Text(timer.isExternalTimerActive ? "This changes the notch display. A timer in Clock keeps running until you stop it there." : "The current timer will be stopped and replaced.")
        }
        .onChange(of: showConfiguration) { _, shown in
            vm.isTimerPopoverActive = shown || replacingTimer
            vm.setAutoCloseSuppression(shown || replacingTimer, token: suppressionToken)
        }
        .onChange(of: replacingTimer) { _, shown in
            vm.isTimerPopoverActive = shown || showConfiguration
            vm.setAutoCloseSuppression(shown || showConfiguration, token: suppressionToken)
        }
        .onDisappear {
            vm.isTimerPopoverActive = false
            vm.setAutoCloseSuppression(false, token: suppressionToken)
            vm.setScrollGestureSuppression(false, token: suppressionToken)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Timers").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(statusLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if section != .stopwatch {
                Button { showConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).font(.system(size: 12)).help("Duration and session settings")
            }
            primaryAction
        }
    }

    private var navigation: some View {
        HStack(spacing: 18) {
            ForEach(TimerSection.allCases) { value in
                let selected = section == value
                Button { storedSection = value.rawValue } label: {
                    VStack(spacing: 3) {
                        Text(value.rawValue).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                        Capsule().fill(selected ? appearance.accentColor : .clear).frame(height: 2)
                    }.fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLabel: String {
        switch section {
        case .timer: return timer.isTimerActive ? timer.timerName : "New timer"
        case .pomodoro: return modes.pomodoro.isActive ? "\(modes.pomodoro.completedFocusSessions) completed" : "New pomodoro"
        case .stopwatch: return modes.stopwatch.isRunning ? "Running" : (modes.stopwatch.hasStarted ? "Paused" : "Ready")
        }
    }

    @ViewBuilder private var primaryAction: some View {
        switch section {
        case .timer:
            if timer.isTimerActive {
                if timer.allowsManualInteraction {
                    actionPill(timer.isPaused ? "Resume" : "Pause", icon: timer.isPaused ? "play.fill" : "pause.fill") {
                        if modes.ownsDisplayedTimer {
                            timer.isPaused ? modes.resumePomodoro() : modes.pausePomodoro()
                        } else { timer.isPaused ? timer.resumeTimer() : timer.pauseTimer() }
                    }
                }
            } else { actionPill("Start", icon: "play.fill") { requestStart(.timer) }.disabled(timerDuration <= 0) }
        case .pomodoro:
            if modes.ownsDisplayedTimer {
                actionPill(modes.pomodoro.isPaused ? "Resume" : "Pause", icon: modes.pomodoro.isPaused ? "play.fill" : "pause.fill") {
                    modes.pomodoro.isPaused ? modes.resumePomodoro() : modes.pausePomodoro()
                }
            } else { actionPill("Start", icon: "play.fill") { requestStart(.pomodoro) } }
        case .stopwatch:
            actionPill(modes.stopwatch.isRunning ? "Pause" : (modes.stopwatch.hasStarted ? "Resume" : "Start"),
                       icon: modes.stopwatch.isRunning ? "pause.fill" : "play.fill") {
                modes.stopwatch.isRunning ? modes.pauseStopwatch() : modes.startStopwatch()
            }
        }
    }

    private func actionPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(appearance.accentColor)
                .background {
                    NotchElementSurface(cornerRadius: 20)
                        .overlay(appearance.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                .overlay { Capsule().stroke(appearance.accentColor.opacity(0.35), lineWidth: 1) }
        }.buttonStyle(.plain)
    }

    private var countdownContent: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(timer.isTimerActive ? timer.formattedRemainingTime() : format(timerDuration))
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(timer.isOvertime ? Color.red : Color.white)
                Spacer()
                if timer.isTimerActive {
                    if timer.allowsManualInteraction {
                        Button("End", role: .destructive) {
                            if modes.ownsDisplayedTimer { modes.stopPomodoro() } else { timer.forceStopTimer() }
                        }.font(.caption).buttonStyle(.plain)
                    } else { Text("Controlled by Clock").font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Menu("Presets") {
                        ForEach(presets) { preset in
                            Button(preset.name) { timerDuration = preset.duration }
                        }
                        if presets.isEmpty { Text("Add presets in Timer settings") }
                    }.font(.caption).menuStyle(.borderlessButton).fixedSize()
                }
            }
            if timer.isTimerActive {
                ProgressView(value: min(max(timer.progress, 0), 1)).tint(timer.isOvertime ? .red : appearance.accentColor)
                Text(timer.isPaused ? "Paused" : "Timer continues while the notch is closed")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                CompactDurationRuler(minutes: Binding(get: { timerDuration / 60 }, set: { timerDuration = $0 * 60 }), accent: appearance.accentColor)
                Text("Drag the ruler · use settings for hours and seconds").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var pomodoroContent: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(modes.pomodoro.isActive ? format(modes.pomodoro.remaining(at: Date())) : format(focusMinutes * 60))
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(modes.pomodoro.isActive ? modes.pomodoro.phase.title.lowercased() : "of focus")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(appearance.accentColor)
                Spacer()
                if modes.pomodoro.isActive {
                    Button("Reset", role: .destructive) { modes.stopPomodoro() }.font(.caption).buttonStyle(.plain)
                }
            }
            if modes.pomodoro.isActive {
                ProgressView(value: min(1, max(0, 1 - modes.pomodoro.remaining(at: Date()) / modes.pomodoro.phaseDuration)))
                    .tint(appearance.accentColor)
                Text(modes.pomodoro.isPaused ? "Paused" : "Next session starts automatically")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                CompactDurationRuler(minutes: $focusMinutes, accent: appearance.accentColor)
            }
            Text("\(Int(shortBreakMinutes))m break · \(Int(longBreakMinutes))m long break after every \(sessionsBeforeLongBreak) sessions · no session limit")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private var stopwatchContent: some View {
        VStack(spacing: 9) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !modes.stopwatch.isRunning)) { context in
                Text(formatStopwatch(modes.stopwatch.elapsed(at: context.date)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("Counts elapsed time, including while hidden").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Reset", role: .destructive) { modes.resetStopwatch() }
                    .font(.caption).buttonStyle(.plain).disabled(!modes.stopwatch.hasStarted)
            }
            Spacer(minLength: 0)
        }
    }

    private var configurationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section == .pomodoro ? "Pomodoro settings" : "Timer duration").font(.headline)
            if section == .pomodoro {
                Stepper("Focus: \(Int(focusMinutes)) min", value: $focusMinutes, in: 1...90)
                Stepper("Short break: \(Int(shortBreakMinutes)) min", value: $shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(Int(longBreakMinutes)) min", value: $longBreakMinutes, in: 1...120)
                Stepper("Long break every \(sessionsBeforeLongBreak) sessions", value: $sessionsBeforeLongBreak, in: 1...12)
                if modes.pomodoro.isActive { Text("End the current Pomodoro to change its durations.").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack {
                    durationField("Hours", unit: 3600, maximum: 23)
                    durationField("Minutes", unit: 60, maximum: 59)
                    durationField("Seconds", unit: 1, maximum: 59)
                }
            }
        }
        .font(.system(size: 12))
        .disabled(section == .pomodoro && modes.pomodoro.isActive)
        .padding(16).frame(width: 280)
        .tint(appearance.accentColor)
    }

    private func durationField(_ title: String, unit: Int, maximum: Int) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption)
            TextField("0", value: Binding(get: {
                (Int(timerDuration) / unit) % (unit == 3600 ? 24 : 60)
            }, set: { value in
                let current = Int(timerDuration)
                let old = (current / unit) % (unit == 3600 ? 24 : 60)
                timerDuration = Double(max(0, current + (min(max(value, 0), maximum) - old) * unit))
            }), format: .number)
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
        }
    }

    private func requestStart(_ section: TimerSection) {
        pendingStart = section
        if timer.isTimerActive { replacingTimer = true } else { begin(section) }
    }
    private func begin(_ section: TimerSection) {
        showConfiguration = false
        DynamicIslandViewCoordinator.shared.timerLiveActivityEnabled = true
        if section == .pomodoro { modes.startPomodoro(configuration: configuration) }
        else { modes.startNormalTimer(duration: max(1, timerDuration)) }
    }
    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(ceil(interval)))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    private func formatStopwatch(_ interval: TimeInterval) -> String {
        let tenths = max(0, Int(interval * 10))
        let seconds = tenths / 10
        let base = seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return "\(base).\(tenths % 10)"
    }
}

private struct CompactDurationRuler: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Binding var minutes: Double
    let accent: Color
    @State private var dragStart: Double?
    @State private var token = UUID()
    private let spacing: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let center = size.width / 2
            let selected = min(90, max(1, minutes))
            let span = Int(ceil(size.width / (2 * spacing))) + 2
            let lower = max(1, Int(selected) - span), upper = min(90, Int(selected) + span)
            for minute in lower...max(lower, upper) {
                let x = center + CGFloat(Double(minute) - selected) * spacing
                let major = minute % 5 == 0
                let height: CGFloat = major ? 15 : 8
                let path = Path(roundedRect: CGRect(x: x, y: 19 - height, width: minute == Int(selected.rounded()) ? 3 : 1.5, height: height), cornerRadius: 1)
                context.fill(path, with: .color(accent.opacity(minute == Int(selected.rounded()) ? 1 : 0.45)))
                if major {
                    context.draw(Text("\(minute)").font(.system(size: 9)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x, y: 29))
                }
            }
            context.stroke(Path { path in path.move(to: CGPoint(x: 0, y: 20)); path.addLine(to: CGPoint(x: size.width, y: 20)) }, with: .color(accent.opacity(0.25)), lineWidth: 1)
            context.fill(Path(roundedRect: CGRect(x: center - 1.5, y: 0, width: 3, height: 21), cornerRadius: 1), with: .color(accent))
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3).onChanged { value in
            if dragStart == nil {
                dragStart = minutes
                vm.setAutoCloseSuppression(true, token: token)
            }
            minutes = min(90, max(1, ((dragStart ?? minutes) - Double(value.translation.width / spacing)).rounded()))
        }.onEnded { _ in
            dragStart = nil
            vm.setAutoCloseSuppression(false, token: token)
        })
        .onHover { vm.setScrollGestureSuppression($0, token: token) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duration in minutes")
        .accessibilityValue("\(Int(minutes))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(90, minutes + 1)
            case .decrement: minutes = max(1, minutes - 1)
            @unknown default: break
            }
        }
        .frame(height: 37)
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: token)
            vm.setAutoCloseSuppression(false, token: token)
        }
    }
}
