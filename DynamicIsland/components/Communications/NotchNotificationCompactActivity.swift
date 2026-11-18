// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import Defaults
import SwiftUI

/// A new notification in the closed notch: the app icon and sender on the
/// left wing, the message on the right, the camera kept clear in between.
/// Clicking or hovering opens the Notifications tab on it.
struct NotchNotificationCompactActivity: View {
    let notification: NotchNotification
    let cameraWidth: CGFloat
    let height: CGFloat
    @Default(.communicationShowPreviews) private var showPreviews
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                NotificationAppIcon(bundleIdentifier: notification.bundleIdentifier,
                                    appName: notification.appName,
                                    size: max(16, min(20, height - 8)))
                Text(showPreviews ? notification.headline : notification.appName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)

            Color.clear.frame(width: max(0, cameraWidth))

            VStack(alignment: .leading, spacing: 1) {
                Text(showPreviews ? notification.body : "New notification")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(width: 130, alignment: .leading)
        }
        .frame(height: max(24, height))
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.snappy(duration: 0.3)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.appName): \(notification.headline). \(notification.body)")
        .accessibilityHint("Open the notch to reply or dismiss")
    }
}
