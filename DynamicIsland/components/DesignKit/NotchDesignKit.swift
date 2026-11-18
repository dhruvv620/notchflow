// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

/// One set of measurements and type styles for every tab, so the notch reads
/// as one product rather than a dozen screens built at different times.
enum NotchTokens {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 12
        static let row: CGFloat = 9
        static let field: CGFloat = 14
        static let chip: CGFloat = 10
    }

    enum Typography {
        /// Tab titles ("Notifications", "WhatsApp").
        static let title = Font.system(size: 13, weight: .semibold)
        /// The first line of a card or row.
        static let headline = Font.system(size: 12, weight: .semibold)
        static let body = Font.system(size: 11)
        static let bodyEmphasis = Font.system(size: 11, weight: .medium)
        static let caption = Font.system(size: 10)
        static let captionEmphasis = Font.system(size: 10, weight: .semibold)
        static let badge = Font.system(size: 10, weight: .semibold).monospacedDigit()
    }

    /// The padding every tab leaves around its content.
    static let tabInsets = EdgeInsets(top: 2, leading: 12, bottom: 6, trailing: 12)

    /// Shared motion, so every panel moves with the same feel.
    enum Motion {
        static let standard = Animation.snappy(duration: 0.28)
        static let hover = Animation.easeOut(duration: 0.15)
        static let height = Animation.smooth(duration: NotchTabHeightPolicy.animationDuration)
    }
}

// MARK: - Surfaces

/// The standard card: element surface, rounded corners, consistent padding,
/// and an optional accent outline for a highlighted item.
struct NotchCard<Content: View>: View {
    var padding: CGFloat = NotchTokens.Spacing.m
    var cornerRadius: CGFloat = NotchTokens.Radius.card
    var isHighlighted = false
    @ViewBuilder var content: () -> Content
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { NotchElementSurface(cornerRadius: cornerRadius) }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(appearance.accentColor.opacity(isHighlighted ? 0.7 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// A list row: leading visual, title and subtitle, trailing accessory.
struct NotchRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var isSelected = false
    var action: (() -> Void)? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @State private var isHovering = false

    var body: some View {
        let row = HStack(spacing: NotchTokens.Spacing.m) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(NotchTokens.Typography.headline)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(NotchTokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: NotchTokens.Spacing.xs)
            trailing()
        }
        .padding(.horizontal, NotchTokens.Spacing.s)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.14 : (isHovering ? 0.08 : 0.05)))
        )
        .contentShape(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous))
        .onHover { hovering in withAnimation(NotchTokens.Motion.hover) { isHovering = hovering } }

        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - Small controls

/// A count or status capsule.
struct NotchBadge: View {
    let text: String
    var tint: Color? = nil
    var filled = false

    var body: some View {
        Text(text)
            .font(NotchTokens.Typography.badge)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(minWidth: 16, minHeight: 16)
            .foregroundStyle(filled ? Color.black : (tint ?? Color.primary))
            .background(Capsule().fill(filled ? (tint ?? .white) : (tint ?? .white).opacity(0.14)))
    }
}

/// A selectable filter capsule.
struct NotchChip<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        Button(action: action) {
            label()
                .font(NotchTokens.Typography.captionEmphasis)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(isSelected ? appearance.accentColor.opacity(0.28) : Color.white.opacity(0.07)))
                .foregroundStyle(isSelected ? appearance.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A round, icon-only button that lights up on hover.
struct NotchIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 22
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A labelled capsule button; `prominent` uses the accent.
struct NotchPillButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    let action: () -> Void
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(NotchTokens.Typography.captionEmphasis)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .foregroundStyle(prominent ? appearance.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var fill: Color {
        if prominent { return appearance.accentColor.opacity(isHovering ? 0.34 : 0.25) }
        return Color.white.opacity(isHovering ? 0.14 : 0.08)
    }
}

/// A small header above a group of rows, with an optional trailing control.
struct NotchSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Text(title)
                .font(NotchTokens.Typography.captionEmphasis)
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, NotchTokens.Spacing.xs)
    }
}

extension NotchSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// The empty, setup and error state every tab shows the same way.
struct NotchEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var showsProgress = false
    @ViewBuilder var actions: () -> Actions
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        VStack(spacing: NotchTokens.Spacing.s) {
            if showsProgress {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(appearance.accentColor.opacity(0.9))
            }
            Text(title)
                .font(NotchTokens.Typography.title)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(NotchTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: NotchTokens.Spacing.m, content: actions)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension NotchEmptyState where Actions == EmptyView {
    init(symbol: String, title: String, detail: String? = nil, showsProgress: Bool = false) {
        self.init(symbol: symbol, title: title, detail: detail, showsProgress: showsProgress) { EmptyView() }
    }
}

/// A message field with a round send button, used for every inline reply.
struct NotchComposeField: View {
    let placeholder: String
    @Binding var text: String
    var isSending = false
    var isEnabled = true
    let onSend: () -> Void
    var onCancel: (() -> Void)? = nil
    @FocusState.Binding var isFocused: Bool
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    private var canSend: Bool {
        isEnabled && !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...4)
                .focused($isFocused)
                .disabled(!isEnabled || isSending)
                .onSubmit { if canSend { onSend() } }
                .onExitCommand { onCancel?() }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: NotchTokens.Radius.field, style: .continuous))
            Button {
                if canSend { onSend() }
            } label: {
                ZStack {
                    if isSending {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(appearance.accentForegroundColor)
                    }
                }
                .frame(width: 24, height: 24)
                .background(Circle().fill(canSend ? appearance.accentColor : Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send")
            if let onCancel {
                NotchIconButton(symbol: "xmark", help: "Cancel", size: 20, action: onCancel)
            }
        }
    }
}

extension View {
    /// The standard padding inside a tab.
    func notchTabPadding() -> some View {
        padding(NotchTokens.tabInsets)
    }
}
