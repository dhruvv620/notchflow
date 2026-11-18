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

/// A preview under the closed notch for something just copied. It has no
/// buttons: any click opens the notch, which lands on the Copied tab where
/// the actions are.
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
                HStack(spacing: 3) {
                    Text(CopyActionPresentation.shortTitle(suggestion.primary))
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(appearance.accentColor)
            }
            .onHover { manager.holdOpen($0) }
            .help("Open the notch to \(suggestion.primary.title.lowercased())")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Copied \(suggestion.text). Open the notch for \(suggestion.primary.title).")
        }
    }
}

enum CopyActionPresentation {
    /// Wings are narrow: "Track UPS package" becomes "Track".
    static func shortTitle(_ action: CopySuggestionAction) -> String {
        switch action.kind {
        case .copy: return action.title
        case .addToCalendar: return "Add to Calendar"
        case .open: return action.title.hasPrefix("Track") ? "Track" : action.title
        }
    }

    static func kindLabel(_ suggestion: CopySuggestion) -> String {
        switch suggestion.primary.kind {
        case .addToCalendar: return "Date"
        case .copy: return "Sum"
        case .open:
            let title = suggestion.primary.title
            if title.hasPrefix("Track flight") { return "Flight" }
            if title.hasPrefix("Track") { return "Tracking number" }
            if title == "Directions" { return "Address" }
            if title == "Call" { return "Phone number" }
            if title == "Email" { return "E-mail address" }
            return "Copied"
        }
    }
}

/// The temporary Copied tab: what was copied and what to do with it.
struct NotchCopyActionView: View {
    @ObservedObject private var manager = CopyActionManager.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        Group {
            if let suggestion = manager.suggestion {
                VStack(alignment: .leading, spacing: NotchTokens.Spacing.m) {
                    HStack(spacing: NotchTokens.Spacing.s) {
                        Image(systemName: suggestion.primary.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appearance.accentColor)
                        Text(CopyActionPresentation.kindLabel(suggestion))
                            .font(NotchTokens.Typography.title)
                        Spacer(minLength: 0)
                        NotchIconButton(symbol: "xmark", help: "Dismiss", action: manager.dismiss)
                    }
                    NotchCard {
                        Text(suggestion.text)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: NotchTokens.Spacing.m) {
                        ForEach(Array(suggestion.actions.enumerated()), id: \.element.id) { index, action in
                            CopyActionButton(action: action, prominent: index == 0) {
                                manager.perform(action)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Text("Goes away on its own a few seconds after you leave this tab.")
                        .font(NotchTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .notchTabPadding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                NotchEmptyState(symbol: "doc.on.clipboard", title: "Nothing copied")
            }
        }
        .onAppear { manager.copiedTabVisible(true) }
        .onDisappear { manager.copiedTabVisible(false) }
    }
}

private struct CopyActionButton: View {
    let action: CopySuggestionAction
    let prominent: Bool
    let perform: () -> Void
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: perform) {
            Label(action.title, systemImage: action.symbol)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(prominent
                        ? appearance.accentColor.opacity(isHovering ? 1 : 0.88)
                        : Color.white.opacity(isHovering ? 0.16 : 0.1))
                )
                .foregroundStyle(prominent ? appearance.accentForegroundColor : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
