// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

/// Content either side of the closed notch: a leading and a trailing wing of
/// equal width, with the hardware notch kept black in the middle.
struct ClosedNotchWings<Leading: View, Trailing: View>: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    let isHovering: Bool
    var wingWidth: CGFloat = ClosedNotchWingsMetrics.wingWidth
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5, content: leading)
                .frame(width: wingWidth, alignment: .leading)
                .padding(.leading, 6)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))
            HStack(spacing: 5, content: trailing)
                .frame(width: wingWidth, alignment: .trailing)
                .padding(.trailing, 6)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
    }
}

enum ClosedNotchWingsMetrics {
    static let wingWidth: CGFloat = 100
    /// Extra width the closed notch needs for two wings, padding included.
    static let addedWidth: CGFloat = (wingWidth + 6) * 2
}

// MARK: - Distraction meter

struct FocusGuardLiveActivity: View {
    @ObservedObject private var guardian = FocusGuardManager.shared
    let isHovering: Bool
    @State private var pulse = false

    static let amber = Color(red: 1.0, green: 0.68, blue: 0.16)

    var body: some View {
        ClosedNotchWings(isHovering: isHovering) {
            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.amber)
                .opacity(pulse ? 1 : 0.55)
            Text(guardian.source)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        } trailing: {
            Text(FocusGuardPolicy.offTrackLabel(seconds: guardian.offTrackSeconds))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Self.amber)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Off track: \(guardian.source), \(FocusGuardPolicy.offTrackLabel(seconds: guardian.offTrackSeconds))")
    }
}

// MARK: - Copy-to-action

struct CopyActionLiveActivity: View {
    @ObservedObject private var manager = CopyActionManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    let isHovering: Bool

    var body: some View {
        if let suggestion = manager.suggestion {
            ClosedNotchWings(isHovering: isHovering) {
                Image(systemName: suggestion.primary.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                Text(suggestion.text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } trailing: {
                ForEach(suggestion.actions.prefix(isHovering ? 2 : 1)) { action in
                    Button { manager.perform(action) } label: {
                        Text(shortTitle(action))
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(appearance.accentColor))
                            .foregroundStyle(appearance.accentForegroundColor)
                    }
                    .buttonStyle(.plain)
                    .help(action.title)
                }
            }
            .onHover { manager.holdOpen($0) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Copied \(suggestion.text)")
        }
    }

    /// Wings are narrow: "Track UPS package" becomes "Track".
    private func shortTitle(_ action: CopySuggestionAction) -> String {
        switch action.kind {
        case .copy: return action.title
        case .addToCalendar: return "Add"
        case .open:
            if action.title.hasPrefix("Track") { return "Track" }
            return action.title
        }
    }
}

// MARK: - Build watcher

struct BuildWatchLiveActivity: View {
    @ObservedObject private var manager = BuildWatchManager.shared
    let isHovering: Bool

    var body: some View {
        if let run = manager.announcement ?? manager.running.first {
            ClosedNotchWings(isHovering: isHovering) {
                icon(for: run.state)
                Text(run.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            } trailing: {
                if run.state == .running, manager.running.count > 1 {
                    Text("+\(manager.running.count - 1)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(label(for: run.state))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color(for: run.state))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { if run.url != nil { manager.open(run) } }
            .help(run.detail)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(run.title), \(label(for: run.state))")
        }
    }

    @ViewBuilder
    private func icon(for state: WatchedRun.State) -> some View {
        if state == .running {
            ProgressView().controlSize(.mini).tint(.white)
                .frame(width: 12, height: 12)
        } else {
            Image(systemName: state == .success ? "checkmark.circle.fill" : (state == .failure ? "xmark.octagon.fill" : "minus.circle.fill"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color(for: state))
        }
    }

    private func label(for state: WatchedRun.State) -> String {
        switch state {
        case .running: return "Running"
        case .success: return "Passed"
        case .failure: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private func color(for state: WatchedRun.State) -> Color {
        switch state {
        case .running: return .white.opacity(0.75)
        case .success: return .green
        case .failure: return .red
        case .cancelled: return .gray
        }
    }
}
