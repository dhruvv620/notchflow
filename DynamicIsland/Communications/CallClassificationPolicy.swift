// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Deliberately narrow prototype: English, exposed native call controls only.
/// Microphone usage, app audio and window names alone never identify a call.
enum CallClassificationPolicy {
    struct Control: Sendable {
        let labels: [String]
        let enabled: Bool
        let pressable: Bool
    }
    struct Match: Sendable {
        let phase: CommunicationCallPhase
        let actions: [CommunicationCallAction: Int]
    }
    static func normalized(_ text: String) -> String {
        let withoutShortcut = text.components(separatedBy: " (").first ?? text
        return withoutShortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func classify(app: CommunicationApp, context: String, controls: [Control]) -> Match? {
        guard [.faceTime, .phone, .whatsapp, .teams, .zoom].contains(app) else { return nil }
        let context = normalized(context)
        let callContext = ["incoming call", "video call", "voice call", "audio call", "call in progress", "in a call", "facetime", "meeting"].contains { context.contains($0) }
        var hasMeetingEnd = false
        var matches: [CommunicationCallAction: Int] = [:]
        for (index, control) in controls.enumerated() where control.enabled && control.pressable {
            for label in control.labels.map(normalized) {
                let action: CommunicationCallAction?
                switch label {
                case "answer", "answer call", "accept call", "accept audio call", "accept video call": action = .answer
                case "accept" where callContext || app == .faceTime || app == .phone: action = .answer
                case "decline", "decline call", "reject call": action = .decline
                case "end call", "hang up", "leave meeting", "leave call": action = .end
                case "end meeting", "end meeting for all": hasMeetingEnd = true; action = nil
                case "leave" where (app == .teams || app == .zoom) && callContext: action = .end
                case "mute", "mute microphone", "mute my microphone", "mute my audio", "mute audio", "turn microphone off": action = .mute
                case "unmute", "unmute microphone", "unmute my microphone", "unmute my audio", "unmute audio", "turn microphone on": action = .unmute
                case "turn camera off", "turn camera on", "start video", "stop video": action = .toggleVideo
                default: action = nil
                }
                if let action, matches[action] == nil { matches[action] = index }
            }
        }
        if matches[.answer] != nil && matches[.decline] != nil,
           callContext || app == .faceTime || app == .phone {
            return Match(phase: .incoming, actions: matches.filter { [.answer, .decline].contains($0.key) })
        }
        if matches[.end] != nil && (context.contains("connecting") || context.contains("calling") || context.contains("ringing")) {
            return Match(phase: .connecting, actions: [.end: matches[.end]!])
        }
        if (matches[.end] != nil || hasMeetingEnd) && (matches[.mute] != nil || matches[.unmute] != nil) {
            return Match(phase: .active, actions: matches.filter { ![.answer, .decline].contains($0.key) })
        }
        return nil
    }
}
