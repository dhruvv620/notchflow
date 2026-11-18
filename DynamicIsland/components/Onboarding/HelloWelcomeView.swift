// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import SwiftUI

/// "hello" in one continuous cursive stroke, drawn in a 640 x 320 design
/// space and scaled to fit. Trim it to write it out.
struct CursiveHelloLettering: Shape {
    /// The part of the design space the letters use, with room for the pen.
    private static let bounds = CGRect(x: 18, y: 28, width: 520, height: 206)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.bounds.width, rect.height / Self.bounds.height)
        let offsetX = rect.midX - Self.bounds.midX * scale
        let offsetY = rect.midY - Self.bounds.midY * scale
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: offsetX + x * scale, y: offsetY + y * scale) }

        var path = Path()
        // Lead-in and the h
        path.move(to: p(30, 210))
        path.addCurve(to: p(125, 75), control1: p(70, 200), control2: p(120, 120))
        path.addCurve(to: p(92, 60), control1: p(130, 40), control2: p(100, 30))
        path.addCurve(to: p(76, 222), control1: p(82, 100), control2: p(80, 170))
        path.addCurve(to: p(132, 147), control1: p(86, 175), control2: p(110, 145))
        path.addCurve(to: p(152, 210), control1: p(156, 150), control2: p(150, 190))
        // e
        path.addCurve(to: p(192, 208), control1: p(155, 228), control2: p(175, 222))
        path.addCurve(to: p(240, 150), control1: p(214, 190), control2: p(244, 172))
        path.addCurve(to: p(190, 160), control1: p(236, 128), control2: p(200, 130))
        path.addCurve(to: p(222, 222), control1: p(182, 190), control2: p(194, 222))
        // l
        path.addCurve(to: p(292, 120), control1: p(250, 222), control2: p(275, 180))
        path.addCurve(to: p(290, 40), control1: p(305, 70), control2: p(305, 38))
        path.addCurve(to: p(270, 190), control1: p(272, 44), control2: p(266, 120))
        path.addCurve(to: p(305, 218), control1: p(272, 215), control2: p(285, 224))
        // l
        path.addCurve(to: p(365, 120), control1: p(330, 210), control2: p(350, 170))
        path.addCurve(to: p(363, 40), control1: p(378, 70), control2: p(378, 38))
        path.addCurve(to: p(343, 190), control1: p(345, 44), control2: p(339, 120))
        path.addCurve(to: p(380, 216), control1: p(345, 215), control2: p(358, 224))
        // o and the tail
        path.addCurve(to: p(412, 168), control1: p(395, 210), control2: p(405, 190))
        path.addCurve(to: p(458, 150), control1: p(420, 145), control2: p(445, 138))
        path.addCurve(to: p(444, 220), control1: p(474, 166), control2: p(468, 210))
        path.addCurve(to: p(418, 175), control1: p(420, 228), control2: p(408, 200))
        path.addCurve(to: p(462, 160), control1: p(426, 158), control2: p(445, 156))
        path.addCurve(to: p(525, 140), control1: p(485, 165), control2: p(505, 158))
        return path
    }
}

/// Plays the synthesized welcome chime.
@MainActor
enum WelcomeChime {
    private static var player: AVAudioPlayer?

    static func play() {
        guard let player = try? AVAudioPlayer(data: WelcomeChimePolicy.wavData()) else { return }
        Self.player = player
        player.volume = 1
        player.play()
    }
}

/// The animated "hello": the word writes itself with a chime, then fills in
/// with a soft glow. Click it to write it again.
struct CursiveHelloView: View {
    var lineWidth: CGFloat = 9
    var playsSound = true
    var onWritten: (() -> Void)? = nil

    @State private var progress: CGFloat = 0
    @State private var glow = false
    @State private var run = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let writeDuration = 2.6
    private static let colors: [Color] = [
        Color(red: 0.98, green: 0.62, blue: 0.42),
        Color(red: 0.98, green: 0.45, blue: 0.62),
        Color(red: 0.70, green: 0.48, blue: 0.98),
        Color(red: 0.40, green: 0.66, blue: 1.00),
        Color(red: 0.38, green: 0.86, blue: 0.80),
    ]

    var body: some View {
        let gradient = LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing)
        ZStack {
            CursiveHelloLettering()
                .trim(from: 0, to: progress)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .blur(radius: 14)
                .opacity(glow ? 0.55 : 0)
            CursiveHelloLettering()
                .trim(from: 0, to: progress)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .contentShape(Rectangle())
        .onTapGesture { write() }
        .onAppear { write() }
        .accessibilityElement()
        .accessibilityLabel("hello")
    }

    private func write() {
        run += 1
        let thisRun = run
        progress = 0
        glow = false
        if playsSound { WelcomeChime.play() }
        if reduceMotion {
            progress = 1
            glow = true
            onWritten?()
            return
        }
        // Start on the next frame so a replay begins from an empty page.
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.45, 0.05, 0.35, 1, duration: Self.writeDuration)) { progress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDuration * 0.85) {
            guard thisRun == run else { return }
            withAnimation(.easeOut(duration: 0.8)) { glow = true }
            onWritten?()
        }
    }
}

/// First step of onboarding: hello, then a welcome and Get started.
struct HelloWelcomeView: View {
    var onGetStarted: (() -> Void)? = nil
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            CursiveHelloView {
                withAnimation(.easeOut(duration: 0.7)) { showDetails = true }
            }
            .frame(height: 170)
            .padding(.horizontal, 28)

            VStack(spacing: 6) {
                Text("Welcome to NotchFlow")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Your notch, now with music, timers, your clipboard, AI agents and more.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 18)
            .opacity(showDetails ? 1 : 0)
            .offset(y: showDetails ? 0 : 8)

            Spacer()

            Button {
                onGetStarted?()
            } label: {
                Text("Get started")
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .opacity(showDetails ? 1 : 0)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

/// Settings > About can show the hello again.
@MainActor
final class HelloWindowController {
    static let shared = HelloWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.center()
            self.window = window
        }
        // A fresh view each time so the writing starts over.
        window?.contentView = NSHostingView(rootView:
            CursiveHelloView()
                .padding(36)
                .frame(width: 420, height: 300)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        )
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

#Preview {
    HelloWelcomeView()
        .frame(width: 400, height: 600)
}
