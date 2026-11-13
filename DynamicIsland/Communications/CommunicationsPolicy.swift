// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum CommunicationsPolicy {
    static func durationLabel(_ call: CommunicationCall, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(call.connectedAt ?? call.observedAt)))
        let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return call.connectedAt == nil ? "Detected \(time)" : time
    }

    static func priorityCall(_ calls: [CommunicationCall]) -> CommunicationCall? {
        calls.sorted {
            let ranks: [CommunicationCallPhase: Int] = [.incoming: 0, .connecting: 1, .active: 2]
            let first = ranks[$0.phase] ?? 3, second = ranks[$1.phase] ?? 3
            return first == second ? $0.observedAt < $1.observedAt : first < second
        }.first
    }
    static func mergeNotifications(existing: [CommunicationNotification], observed: [CommunicationNotification],
                                   allowedApps: Set<CommunicationApp>, limit: Int) -> [CommunicationNotification] {
        var result: [CommunicationNotification] = []
        var seen = Set<String>()
        for var item in observed.sorted(by: { $0.receivedAt > $1.receivedAt }) where allowedApps.contains(item.app) && seen.insert(item.id).inserted {
            if let previous = existing.first(where: { $0.id == item.id }) { item.receivedAt = previous.receivedAt }
            result.append(item)
        }
        for var item in existing where allowedApps.contains(item.app) && seen.insert(item.id).inserted {
            item.canReply = false; item.canOpen = false; item.canDismiss = false
            result.append(item)
        }
        return Array(result.sorted { $0.receivedAt > $1.receivedAt }.prefix(max(0, limit)))
    }
}
