/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import SwiftUI

/// Announces a new WhatsApp message in the closed notch: the sender's avatar
/// and a message glyph on either side of the notch, and the message itself on
/// a line underneath. Clicking it opens the conversation.
struct WhatsAppMessageLiveActivity: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    let banner: WhatsAppIncomingBanner
    let isHovering: Bool
    let onTap: () -> Void

    @State private var isExpanded = false

    private var wingSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)) }
    private var centerWidth: CGFloat { vm.closedNotchSize.width + (isHovering ? 8 : 0) + 20 }
    private var totalWidth: CGFloat { centerWidth + (isExpanded ? (wingSize + 8) * 2 : 0) }

    private var title: String {
        guard banner.isGroup else { return banner.chatName }
        let sender = banner.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return sender.isEmpty ? banner.chatName : "\(sender) · \(banner.chatName)"
    }

    private var initial: String {
        let letter = banner.chatName.first(where: { $0.isLetter || $0.isNumber }) ?? "#"
        return String(letter).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                WhatsAppAvatar(initial: initial, isGroup: banner.isGroup, size: wingSize)
                    .frame(width: isExpanded ? wingSize + 8 : 0, alignment: .leading)
                    .opacity(isExpanded ? 1 : 0)

                Rectangle()
                    .fill(.black)
                    .frame(width: centerWidth)

                Image(systemName: "message.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.whatsAppGreen)
                    .frame(width: isExpanded ? wingSize + 8 : 0, alignment: .trailing)
                    .opacity(isExpanded ? 1 : 0)
            }
            .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))

            if isExpanded {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(banner.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: max(0, totalWidth - 16))
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("WhatsApp message from \(title): \(banner.text)"))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = true
            }
        }
    }
}
