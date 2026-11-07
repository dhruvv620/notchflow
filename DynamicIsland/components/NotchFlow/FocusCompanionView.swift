// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FocusCompanionView: View {
    @ObservedObject private var model = FocusCompanionModel.shared
    @ObservedObject private var timer = TimerManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = model.image {
                AnimatedFocusImage(image: image, animates: !reduceMotion && !timer.isPaused)
            } else {
                TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion || timer.isPaused)) { context in
                    let phase = reduceMotion || timer.isPaused ? 0 : sin(context.date.timeIntervalSinceReferenceDate * 4)
                    ZStack {
                        RoundedRectangle(cornerRadius: size * 0.14)
                            .fill(.yellow.gradient)
                            .frame(width: size * 0.7, height: size * 0.72)
                        HStack(spacing: size * 0.08) {
                            eye
                            eye
                        }.offset(y: -size * 0.08)
                        Capsule().fill(.brown).frame(width: size * 0.22, height: size * 0.05).offset(y: size * 0.15)
                        HStack(spacing: size * 0.2) {
                            Capsule().fill(.orange).frame(width: size * 0.12, height: size * 0.18)
                            Capsule().fill(.orange).frame(width: size * 0.12, height: size * 0.18)
                        }.offset(y: size * 0.4)
                    }
                    .rotationEffect(.degrees(phase * 5))
                    .offset(y: phase * size * 0.04)
                }
            }
        }.frame(width: size, height: size).accessibilityLabel("Focus companion")
    }
    private var eye: some View {
        ZStack {
            Ellipse().fill(.white).frame(width: size * 0.2, height: size * 0.25)
            Circle().fill(.black).frame(width: size * 0.07)
        }
    }
}

private struct AnimatedFocusImage: NSViewRepresentable {
    let image: NSImage
    let animates: Bool
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image
        view.animates = animates
    }
}

struct FocusNotchView: View {
    @ObservedObject private var model = FocusCompanionModel.shared
    @ObservedObject private var timer = TimerManager.shared
    @AppStorage("notchflowFocusMinutes") private var minutes = 25.0
    @State private var replacingTimer = false
    @State private var pendingMinutes = 25.0
    @State private var pendingFocus = true

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                FocusCompanionView(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.isFocusSession ? timer.timerName.uppercased() : "FOCUS").font(.caption.bold()).foregroundStyle(.orange)
                    Text(model.isFocusSession ? timer.formattedTimeRemaining : String(format: "%02d:00", Int(minutes)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(model.isFocusSession ? timer.statusText : "A little company for your next session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if model.isFocusSession {
                ProgressView(value: min(1, timer.progress)).tint(.orange)
                HStack {
                    Button(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill") {
                        if timer.isPaused { timer.resumeTimer() } else { timer.pauseTimer() }
                    }
                    Button("End session", role: .destructive) { timer.stopTimer() }
                    Spacer()
                    Button("Short break") { requestStart(5, focus: false) }
                }
            } else {
                HStack {
                    Stepper("\(Int(minutes)) min", value: $minutes, in: 1...180, step: 1)
                    Spacer()
                    Button("Start focus", systemImage: "play.fill") { requestStart(minutes, focus: true) }.tint(.orange)
                    Button("5 min break") { requestStart(5, focus: false) }
                    Button("15 min break") { requestStart(15, focus: false) }
                }
            }
            HStack {
                Button("Choose character image / GIF…") { chooseImage() }
                if model.image != nil { Button("Default character") { model.resetImage() } }
                Spacer()
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Your companion appears beside the timer when the notch is closed. Sessions use the existing timer and its sound settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog("Replace the running timer?", isPresented: $replacingTimer) {
            Button("Replace timer") { model.start(minutes: pendingMinutes, focus: pendingFocus) }
        }
    }
    private func requestStart(_ minutes: Double, focus: Bool) {
        pendingMinutes = minutes
        pendingFocus = focus
        if timer.isTimerActive { replacingTimer = true }
        else { model.start(minutes: minutes, focus: focus) }
    }
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.importImage(from: url) }
    }
}
