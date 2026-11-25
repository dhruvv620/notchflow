// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
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
        // Labels differ between apps and versions.
        let faceTimeEnd = CallClassificationPolicy.classify(app: .faceTime, context: "FaceTime Alex", controls: [control("End"), control("Video")])
        try check(faceTimeEnd?.phase == .active && faceTimeEnd?.actions[.end] == 0, "FaceTime's plain End button was not recognized")
        let whatsAppCall = CallClassificationPolicy.classify(app: .whatsapp, context: "Voice call", controls: [control("End call"), control("Mute microphone")])
        try check(whatsAppCall?.phase == .active && whatsAppCall?.actions[.mute] == 1, "WhatsApp call controls were not recognized")
        let hangUp = CallClassificationPolicy.classify(app: .zoom, context: "Meeting", controls: [control("Hang Up"), control("Unmute my audio")])
        try check(hangUp?.actions[.end] == 0 && hangUp?.actions[.unmute] == 1, "Hang Up and Unmute were not recognized")
        try check(CallClassificationPolicy.classify(app: .whatsapp, context: "Chats", controls: [control("End")]) == nil,
                  "An End button outside a call was taken for a call")
        try check(CallClassificationPolicy.action(for: "End Meeting for All", app: .zoom, callContext: true) == nil,
                  "Ending the meeting for everyone was offered as a hang-up")
        let ringing = CallClassificationPolicy.classify(app: .whatsapp, context: "Incoming voice call", controls: [control("Accept"), control("Decline")])
        try check(ringing?.phase == .incoming, "A ringing WhatsApp call was not recognized")

        // Calls found from microphone use: input and output both running.
        func process(_ bundle: String, _ name: String, input: Bool = true, output: Bool = true) -> CallAudioPolicy.Process {
            .init(pid: 1, bundleID: bundle, name: name, input: input, output: output)
        }
        let allApps: Set<CommunicationApp> = [.faceTime, .phone, .whatsapp, .teams, .zoom]
        try check(CallAudioPolicy.callApps(from: [process("", "avconferenced")], allowed: allApps, ownBundleID: "me") == [.faceTime],
                  "A FaceTime or iPhone call was not found from its audio")
        try check(CallAudioPolicy.callApps(from: [process("net.whatsapp.WhatsApp", "WhatsApp")], allowed: allApps, ownBundleID: "me") == [.whatsapp],
                  "A WhatsApp call was not found from its audio")
        try check(CallAudioPolicy.callApps(from: [process("net.whatsapp.WhatsApp", "WhatsApp", output: false)], allowed: allApps, ownBundleID: "me").isEmpty,
                  "Recording a voice note was taken for a call")
        try check(CallAudioPolicy.callApps(from: [process("com.apple.SpeechRecognitionCore", "dictation")], allowed: allApps, ownBundleID: "me").isEmpty,
                  "Dictation was taken for a call")
        try check(CallAudioPolicy.callApps(from: [process("us.zoom.xos", "zoom.us")], allowed: [.whatsapp], ownBundleID: "me").isEmpty,
                  "A call app turned off in Settings was shown")
        try check(CallAudioPolicy.callApps(from: [process("", "avconferenced")], allowed: [.phone], ownBundleID: "me") == [.faceTime],
                  "iPhone calls on: their audio process was ignored")
        try check(CallAudioPolicy.isEndMenuTitle("End Call") && CallAudioPolicy.isEndMenuTitle("Leave Meeting…")
                  && !CallAudioPolicy.isEndMenuTitle("End Meeting for All") && !CallAudioPolicy.isEndMenuTitle("Endnotes"),
                  "End-call menu titles not matched correctly")
        print("Communications priority, retention, stale actions and native call policy checks passed")
    }
}
