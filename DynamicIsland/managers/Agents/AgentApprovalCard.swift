// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// When an agent asks for permission, show a small card at the top right
    /// of the screen with Allow / Deny (no need to open the notch).
    static let agentApprovalCard = Key<Bool>("agentApprovalCard", default: true)
}

/// The approval card: a small floating panel under the menu bar, at the top
/// right, shown only while an agent is waiting on you. It never takes focus
/// from the app you're in.
@MainActor
final class AgentApprovalCard {
    static let shared = AgentApprovalCard()

    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard subscriptions.isEmpty else { return }
        AgentHub.shared.$requests
            .combineLatest(Defaults.publisher(.agentApprovalCard).map(\.newValue),
                           Defaults.publisher(.enableAgentsFeature).map(\.newValue))
            .receive(on: RunLoop.main)
            .sink { [weak self] requests, cardOn, agentsOn in
                if cardOn && agentsOn && !requests.isEmpty { self?.show() } else { self?.hide() }
            }
            .store(in: &subscriptions)
    }

    private static let size = NSSize(width: 360, height: 210)

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        // Top right, under the menu bar, where notifications appear.
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - Self.size.width - 12, y: visible.maxY - Self.size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        if panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                // Shown again meanwhile (a new request): keep it.
                guard panel.alphaValue < 0.05 else { return }
                panel.orderOut(nil)
                // Free the view; it's made again for the next request.
                if AgentApprovalCard.shared.panel === panel { AgentApprovalCard.shared.panel = nil }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        let hosting = FirstClickHostingView(rootView: AgentApprovalCardView())
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
        return panel
    }
}

/// Buttons respond to the first click even though NotchFlow isn't the active app.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct AgentApprovalCardView: View {
    @ObservedObject private var hub = AgentHub.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let request = hub.requests.first {
                content(request)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 210, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private func content(_ request: AgentRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(request.agent.monogram)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(request.agent.tint)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(request.agent.tint.opacity(0.2)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(request.agent.displayName).font(.system(size: 12, weight: .semibold))
                    Text(request.project).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if hub.requests.count > 1 {
                    Text("1 of \(hub.requests.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                Button {
                    DynamicIslandViewCoordinator.shared.currentView = .agents
                    AppDelegate.shared?.vm.open()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in the notch")
            }
            switch request.kind {
            case .permission(let title, let detail, let risk, let canAlwaysAllow):
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let label = risk.label {
                        Text(label)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill((risk == .danger ? Color.red : Color.orange).opacity(0.25)))
                            .foregroundStyle(risk == .danger ? Color.red : Color.orange)
                    }
                }
                if !detail.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 54)
                    .padding(7)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack(spacing: 6) {
                    cardButton("Allow", symbol: "checkmark", fill: Color.green.opacity(0.85), text: .black) {
                        hub.resolve(request, with: .allow)
                    }
                    if canAlwaysAllow {
                        cardButton("Always", symbol: "checkmark.seal", fill: Color.white.opacity(0.12), text: .white) {
                            hub.resolve(request, with: .allowAlways)
                        }
                    }
                    cardButton("Deny", symbol: "xmark", fill: Color.red.opacity(0.22), text: .red) {
                        hub.resolve(request, with: .deny("The user declined this from NotchFlow."))
                    }
                    Spacer(minLength: 0)
                }
            case .question, .ask:
                Text("Has a question for you.").font(.system(size: 13, weight: .semibold))
                cardButton("Answer in the notch", symbol: "bubble.left", fill: Color.white.opacity(0.12), text: .white) {
                    DynamicIslandViewCoordinator.shared.currentView = .agents
                    AppDelegate.shared?.vm.open()
                }
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.08).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(request.agent.tint.opacity(0.45), lineWidth: 1))
        .foregroundStyle(.white)
    }

    private func cardButton(_ title: String, symbol: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .foregroundStyle(text)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
