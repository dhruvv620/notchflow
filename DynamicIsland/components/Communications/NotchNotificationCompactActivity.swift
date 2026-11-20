// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import Defaults
import SwiftUI

/// A new notification in the closed notch: the app's icon beside the notch,
/// and the sender and message on one line under it (like a WhatsApp banner),
/// so the camera never cuts the text. Clicking or hovering opens the
/// Notifications tab on it.
struct NotchNotificationCompactActivity: View {
    let notification: NotchNotification
    let cameraWidth: CGFloat
    let height: CGFloat
    @Default(.communicationShowPreviews) private var showPreviews
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @State private var appeared = false

    /// The line under the notch with who sent it and the message.
    static let messageLineHeight: CGFloat = 24
    private static let messageLineBottomPadding: CGFloat = 8

    private var wingSize: CGFloat { max(16, height - 12) }
    private var centerWidth: CGFloat { cameraWidth + 20 }
    private var totalWidth: CGFloat { centerWidth + (wingSize + 8) * 2 }

    var body: some View {
        VStack(spacing: 0) {
            // Beside the notch: the app's icon, and a dot in the accent color.
            // Nothing is written there, so the camera never cuts the text.
            HStack(spacing: 0) {
                NotificationAppIcon(bundleIdentifier: notification.bundleIdentifier,
                                    appName: notification.appName, size: wingSize)
                    .frame(width: appeared ? wingSize + 8 : 0, alignment: .leading)
                    .opacity(appeared ? 1 : 0)
                Rectangle().fill(.black).frame(width: centerWidth)
                Image(systemName: "bell.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                    .frame(width: appeared ? wingSize + 8 : 0, alignment: .trailing)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(height: height)

            // Under the notch: one line, sender then message.
            if appeared {
                HStack(spacing: 5) {
                    Text(showPreviews ? notification.headline : notification.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(showPreviews ? notification.body : "New notification")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: max(0, totalWidth - 16), height: Self.messageLineHeight - Self.messageLineBottomPadding)
                .padding(.bottom, Self.messageLineBottomPadding)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.appName): \(notification.headline). \(notification.body)")
        .accessibilityHint("Open the notch to reply or dismiss")
    }
}
