// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main
struct CommunicationsRegression {
    static func main() throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "CommunicationsRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let now = Date(timeIntervalSince1970: 1000)
        func call(_ id: String, _ phase: CommunicationCallPhase) -> CommunicationCall {
            CommunicationCall(id: id, app: .faceTime, caller: "Alex", phase: phase, connectedAt: nil, observedAt: now, actions: [.open])
        }
        try check(CommunicationsPolicy.priorityCall([call("active", .active), call("ring", .incoming)])?.id == "ring", "Incoming call did not preempt ongoing call")
        try check(CommunicationsPolicy.priorityCall([]) == nil, "No call created a synthetic island")
        try check(CommunicationsPolicy.durationLabel(call("x", .active), now: now.addingTimeInterval(65)) == "Detected 01:05", "Unknown connected time was shown as exact call duration")
        func message(_ id: String, _ date: Date) -> CommunicationNotification {
            CommunicationNotification(id: id, app: .messages, sender: "Alex", body: "Hi", receivedAt: date, canReply: true, canOpen: true, canDismiss: true)
        }
        let history = (0..<25).map { message("\($0)", now.addingTimeInterval(Double($0))) }
        let merged = CommunicationsPolicy.mergeNotifications(existing: history, observed: [message("new", now.addingTimeInterval(40))], allowedApps: [.messages], limit: 20)
        try check(merged.count == 20 && merged[0].id == "new", "Inbox did not retain bounded newest observations")
        try check(!merged[1].canReply && !merged[1].canOpen && !merged[1].canDismiss, "Historical cards retained stale native controls")
        let repeatObservation = CommunicationsPolicy.mergeNotifications(existing: [message("same", now)], observed: [message("same", now.addingTimeInterval(10))], allowedApps: [.messages], limit: 20)
        try check(repeatObservation.count == 1 && repeatObservation[0].receivedAt == now, "Repeated scan duplicated or retimed a notification")
        try check(CommunicationsPolicy.mergeNotifications(existing: history, observed: [], allowedApps: [.whatsapp], limit: 20).isEmpty, "Disabled source retained readable notifications")
        func control(_ title: String) -> CallClassificationPolicy.Control { .init(labels: [title], enabled: true, pressable: true) }
        try check(CallClassificationPolicy.classify(app: .zoom, context: "Microphone in use", controls: [control("Mute")]) == nil, "Microphone use was mistaken for a call")
        let incoming = CallClassificationPolicy.classify(app: .faceTime, context: "Incoming call", controls: [control("Answer"), control("Decline")])
        try check(incoming?.phase == .incoming && incoming?.actions[.answer] == 0, "Native incoming controls were not recognized")
        let active = CallClassificationPolicy.classify(app: .teams, context: "Meeting", controls: [control("Leave"), control("Mute")])
        try check(active?.phase == .active && active?.actions[.end] == 0, "Verified meeting controls were not recognized")
        let host = CallClassificationPolicy.classify(app: .zoom, context: "Meeting", controls: [control("End meeting for all"), control("Mute")])
        try check(host?.phase == .active && host?.actions[.end] == nil, "Host-wide destructive action was exposed as ordinary hangup")
        let connecting = CallClassificationPolicy.classify(app: .faceTime, context: "Connecting", controls: [control("End call"), control("Mute")])
        try check(connecting?.phase == .connecting, "Connecting call was shown as confirmed active")
        print("Communications priority, retention, stale actions and native call policy checks passed")
    }
}
