// SPDX-License-Identifier: GPL-3.0-or-later
import Defaults
import SwiftUI

/// Wings leave the physical camera clear. Tap/hover expands the existing panel.
struct CommunicationCompactActivity: View {
    let call: CommunicationCall?
    let notification: CommunicationNotification?
    let cameraWidth: CGFloat
    let height: CGFloat
    @Default(.communicationShowPreviews) private var showPreviews
    private var app: CommunicationApp { call?.app ?? notification?.app ?? .messages }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: app.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(call?.phase == .incoming ? Color.green : Color.accentColor)
                .frame(width: 28)
            Color.clear.frame(width: max(0, cameraWidth))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                if let call, call.phase == .active {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(CommunicationsPolicy.durationLabel(call, now: context.date))
                            .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 130, alignment: .leading)
        }
        .frame(height: max(24, height))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open the notch for controls")
    }
    private var title: String {
        guard showPreviews else { return call == nil ? "New notification" : "Call" }
        return call?.caller ?? notification?.sender ?? app.title
    }
    private var subtitle: String {
        if let call { return call.phase == .incoming ? "Incoming · \(app.title)" : "Connecting · \(app.title)" }
        return showPreviews ? (notification?.body ?? app.title) : app.title
    }
}
