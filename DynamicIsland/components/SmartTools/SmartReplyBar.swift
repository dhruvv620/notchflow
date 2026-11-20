// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

/// Three suggested replies above a reply field. Nothing is sent to the AI
/// until the sparkles button is tapped; tapping a suggestion fills the field
/// so it can be edited before sending.
struct SmartReplyBar: View {
    /// Identifies the conversation or notification the suggestions belong to.
    let id: String
    let sender: String
    let message: String
    var context: [String] = []
    @Binding var text: String
    @ObservedObject private var service = SmartReplyService.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Default(.enableSmartReplies) private var enabled
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var swipeToken = UUID()

    var body: some View {
        if enabled, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(spacing: NotchTokens.Spacing.xs) {
                Button {
                    service.suggest(id: id, sender: sender, message: message, context: context)
                } label: {
                    Group {
                        if service.loading.contains(id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(appearance.accentColor)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .disabled(service.loading.contains(id))
                .help(service.suggestions[id] == nil ? "Suggest replies with AI" : "Suggest different replies")

                if let error = service.errors[id] {
                    Text(error)
                        .font(NotchTokens.Typography.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(error)
                } else if let suggestions = service.suggestions[id] {
                    // Swipe with two fingers to see them all; over here, a swipe doesn't change the tab.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NotchTokens.Spacing.xs) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                NotchChip(isSelected: text == suggestion, action: { text = suggestion }) {
                                    Text(suggestion).lineLimit(1)
                                }
                                .help(suggestion)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 3)
                    }
                    .onHover { vm.setHorizontalScrollOwnership($0, token: swipeToken) }
                    .onDisappear { vm.setHorizontalScrollOwnership(false, token: swipeToken) }
                } else if !service.loading.contains(id) {
                    Text("Suggest replies")
                        .font(NotchTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 28)
            .padding(.top, 4)
        }
    }
}
