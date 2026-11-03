// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
struct DVNotchyPanel: View {
    @ObservedObject var vm: DynamicIslandViewModel
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var pomodoro = DVPomodoroModel.shared
    @ObservedObject private var appearance = DVAppearanceModel.shared
    @ObservedObject private var lockScreen = LockScreenManager.shared
    @State private var selectedTab: Tab = .music
    @AppStorage("dv.phaseSound") private var phaseSound = true
    private enum Tab { case music, pomodoro, customize }

    private var cameraHeight: CGFloat { max(30, getClosedNotchSize(screen: vm.screen).height) }

    var body: some View {
        Group {
            switch vm.dvPresentation {
            case .idle: idleView
            case .preview: previewView
            case .expanded: expandedView
            }
        }
        .frame(width: vm.dvNotchSize.width, height: vm.dvNotchSize.height, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .opacity(lockScreen.isLocked || (vm.dvPresentation == .idle && vm.hideOnClosed) ? 0 : 1)
        .onChange(of: vm.dvPresentation) { oldValue, newValue in
            if newValue == .expanded && oldValue != .expanded { selectedTab = .music }
        }
    }

    private var idleView: some View {
        HStack {
            idleAnimation(active: !lockScreen.isLocked && !vm.hideOnClosed)
                .frame(width: 32, height: 24)
            Spacer(minLength: getClosedNotchSize(screen: vm.screen).width)
            Group {
                if pomodoro.engine.isRunning {
                    Text(pomodoro.timeText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pomodoro " + pomodoro.timeText)
                } else {
                    Image(systemName: music.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: 38)
        }
        .padding(.horizontal, 12)
        .frame(height: cameraHeight)
        .accessibilityLabel("NotchFlow. Hover for music; click to expand.")
    }

    private var previewView: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: cameraHeight)
            HStack(spacing: 10) {
                artwork(size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.hasActiveSession ? music.songTitle : "Nothing playing")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(music.hasActiveSession ? music.artistName : "Click for Music and Pomodoro")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                transportButton(music.isPlaying ? "pause.fill" : "play.fill",
                                label: music.isPlaying ? "Pause" : "Play", size: 14) { music.playPause() }
                transportButton("forward.fill", label: "Next track", size: 12) { music.nextTrack() }
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("DVPreview")
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: cameraHeight)
            HStack(spacing: 8) {
                tabButton("Music", symbol: "music.note", tab: .music)
                tabButton("Pomodoro", symbol: "timer", tab: .pomodoro)
                Spacer()
                Button {
                    selectedTab = .customize
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 28, height: 28)
                        .background(selectedTab == .customize ? Color.white.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Customize GIF and Pomodoro")
                .accessibilityLabel("Customize")
                Button { vm.sendDVEvent(.cancelled) } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close panel")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            Divider().overlay(.white.opacity(0.08))
            Group {
                switch selectedTab {
                case .music: musicPage
                case .pomodoro: pomodoroPage
                case .customize: customizationPage
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("DVExpanded")
    }

    private var musicPage: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                artwork(size: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text(music.hasActiveSession ? music.songTitle : "Nothing playing")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                    Text(music.hasActiveSession ? music.artistName : "Start music in your player")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let duration = validDuration(music.songDuration)
                let position = validPosition(music.estimatedPlaybackPosition(at: context.date), duration: duration)
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { position }, set: { music.seek(to: $0) }),
                           in: 0...max(1, duration))
                        .tint(.white)
                        .disabled(duration == 0)
                        .accessibilityLabel("Playback position")
                    HStack {
                        Text(duration > 0 ? timeString(position) : (music.hasActiveSession ? "Live" : "--:--"))
                        Spacer()
                        Text(duration > 0 ? timeString(duration) : "")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 30) {
                transportButton("backward.fill", label: "Previous track", size: 19) { music.previousTrack() }
                transportButton(music.isPlaying ? "pause.fill" : "play.fill",
                                label: music.isPlaying ? "Pause" : "Play", size: 27) { music.playPause() }
                transportButton("forward.fill", label: "Next track", size: 19) { music.nextTrack() }
            }
            if pomodoro.engine.isRunning {
                Label(pomodoro.engine.phase.title + "  " + pomodoro.timeText, systemImage: "timer")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var pomodoroPage: some View {
        VStack(spacing: 12) {
            Text(pomodoro.engine.phase.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(pomodoro.engine.phase == .focus ? .orange : .green)
            Text(pomodoro.timeText)
                .font(.system(size: 48, weight: .light, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Time remaining " + pomodoro.timeText)
            ProgressView(value: pomodoro.progress)
                .tint(pomodoro.engine.phase == .focus ? .orange : .green)
            HStack(spacing: 16) {
                Button("Reset") { pomodoro.reset() }
                Button(pomodoro.engine.isRunning ? "Pause" : "Start") { pomodoro.toggleRunning() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                Button("Skip") { pomodoro.skip() }
            }
            Text("Completed focus sessions: \(pomodoro.engine.completedFocusSessions)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Focus and breaks continue while this panel is closed.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var customizationPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    idleAnimation(active: true).frame(width: 42, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Idle animation").font(.system(size: 12, weight: .semibold))
                        Text(appearance.gifURL == nil ? "Default animation" : "Custom GIF")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose GIF…") { appearance.chooseGIF(viewModel: vm) }
                    if appearance.gifURL != nil {
                        Button { appearance.removeGIF() } label: { Image(systemName: "trash") }
                            .help("Remove custom GIF")
                    }
                }
                if let message = appearance.errorMessage {
                    Text(message).font(.system(size: 10)).foregroundStyle(.red)
                }
                Divider()
                durationControl("Focus", value: pomodoro.engine.configuration.focusMinutes, range: 1...240) {
                    updateConfiguration(focus: $0)
                }
                durationControl("Short break", value: pomodoro.engine.configuration.shortBreakMinutes, range: 1...60) {
                    updateConfiguration(shortBreak: $0)
                }
                durationControl("Long break", value: pomodoro.engine.configuration.longBreakMinutes, range: 1...120) {
                    updateConfiguration(longBreak: $0)
                }
                Stepper(value: Binding(get: { pomodoro.engine.configuration.sessionsBeforeLongBreak },
                                       set: { updateConfiguration(sessions: $0) }), in: 1...12) {
                    Text("Focus sessions per long break: \(pomodoro.engine.configuration.sessionsBeforeLongBreak)")
                        .font(.system(size: 11))
                }
                .disabled(pomodoro.engine.isRunning)
                Toggle("Sound when a phase finishes", isOn: $phaseSound)
                    .font(.system(size: 11))
                Text("Changing durations resets the current cycle. Pause first to edit.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Button("More settings…") { SettingsWindowController.shared.showWindow() }
                    .font(.system(size: 11))
            }
        }
    }

    private func tabButton(_ title: String, symbol: String, tab: Tab) -> some View {
        Button { selectedTab = tab } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 11).frame(height: 28)
                .background(selectedTab == tab ? Color.white.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func transportButton(_ symbol: String, label: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
                .frame(width: max(24, size + 10), height: max(28, size + 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func artwork(size: CGFloat) -> some View {
        Image(nsImage: music.albumArt).resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size / 5))
    }

    @ViewBuilder private func idleAnimation(active: Bool) -> some View {
        if let url = appearance.gifURL {
            DVAnimatedGIF(url: url, isActive: active)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .symbolEffect(.pulse, options: .repeating, isActive: active)
        }
    }

    private func durationControl(_ title: String, value: Int, range: ClosedRange<Int>,
                                 change: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: change), in: range) {
            Text("\(title): \(value) min").font(.system(size: 11))
        }
        .disabled(pomodoro.engine.isRunning)
    }

    private func updateConfiguration(focus: Int? = nil, shortBreak: Int? = nil,
                                     longBreak: Int? = nil, sessions: Int? = nil) {
        let c = pomodoro.engine.configuration
        pomodoro.setConfiguration(.init(focusMinutes: focus ?? c.focusMinutes,
            shortBreakMinutes: shortBreak ?? c.shortBreakMinutes,
            longBreakMinutes: longBreak ?? c.longBreakMinutes,
            sessionsBeforeLongBreak: sessions ?? c.sessionsBeforeLongBreak))
    }

    private func validDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite && duration > 0 && duration < 604800 ? duration : 0
    }

    private func validPosition(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        position.isFinite ? min(duration, max(0, position)) : 0
    }

    private func timeString(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
private struct DVAnimatedGIF: NSViewRepresentable {
    let url: URL
    let isActive: Bool

    final class Coordinator { var loadedURL: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if context.coordinator.loadedURL != url {
            view.image = NSImage(contentsOf: url)
            context.coordinator.loadedURL = url
        }
        view.animates = isActive
    }
}
