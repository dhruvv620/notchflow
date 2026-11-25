// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
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
    /// What a call control does, from its label. Labels differ between apps and
    /// versions ("End", "End Call", "Hang Up", "Leave"), so this matches words,
    /// not exact strings. "End meeting for all" is never a plain hang-up.
    static func action(for label: String, app: CommunicationApp, callContext: Bool) -> CommunicationCallAction? {
        let text = normalized(label)
        guard !text.isEmpty, text.count <= 40 else { return nil }
        if text.contains("for all") || text.contains("for everyone") { return nil }
        if ["answer", "answer call", "accept call", "accept audio call", "accept video call", "pick up"].contains(text)
            || text.hasPrefix("answer ") || text.hasPrefix("accept call") { return .answer }
        if text == "accept" && (callContext || app == .faceTime || app == .phone || app == .whatsapp) { return .answer }
        if ["decline", "decline call", "reject", "reject call", "ignore", "ignore call"].contains(text)
            || text.hasPrefix("decline ") { return .decline }
        if ["end call", "end", "hang up", "hangup", "leave call", "leave meeting", "end video call", "end audio call",
            "end voice call"].contains(text) || text.hasPrefix("end call") || text.hasPrefix("hang up") { return .end }
        if text == "leave" && (app == .teams || app == .zoom || callContext) { return .end }
        if text.hasPrefix("unmute") || text == "turn microphone on" || text == "turn on microphone" { return .unmute }
        if text.hasPrefix("mute") || text == "turn microphone off" || text == "turn off microphone"
            || text == "microphone" || text == "mic" { return .mute }
        if text.contains("camera") || ["video", "start video", "stop video", "turn video on", "turn video off"].contains(text) {
            return .toggleVideo
        }
        return nil
    }

    static func classify(app: CommunicationApp, context: String, controls: [Control]) -> Match? {
        guard [.faceTime, .phone, .whatsapp, .teams, .zoom].contains(app) else { return nil }
        let context = normalized(context)
        let callContext = ["incoming call", "video call", "voice call", "audio call", "call in progress", "in a call",
                           "facetime", "meeting", "calling", "ringing"].contains { context.contains($0) }
        var hasMeetingEnd = false
        var matches: [CommunicationCallAction: Int] = [:]
        for (index, control) in controls.enumerated() where control.enabled && control.pressable {
            for label in control.labels {
                let text = normalized(label)
                if text == "end meeting" || text.hasPrefix("end meeting for") { hasMeetingEnd = true; continue }
                if let action = action(for: text, app: app, callContext: callContext), matches[action] == nil {
                    matches[action] = index
                }
            }
        }
        if matches[.answer] != nil && matches[.decline] != nil,
           callContext || app == .faceTime || app == .phone || app == .whatsapp {
            return Match(phase: .incoming, actions: matches.filter { [.answer, .decline].contains($0.key) })
        }
        if matches[.end] != nil && (context.contains("connecting") || context.contains("calling") || context.contains("ringing")) {
            return Match(phase: .connecting, actions: [.end: matches[.end]!])
        }
        let hasMic = matches[.mute] != nil || matches[.unmute] != nil
        // FaceTime and WhatsApp call windows don't always label their mute button;
        // an End button in their call window is enough there.
        let endIsEnough = [.faceTime, .phone, .whatsapp].contains(app) && callContext
        if (matches[.end] != nil || hasMeetingEnd) && (hasMic || endIsEnough) {
            return Match(phase: .active, actions: matches.filter { ![.answer, .decline].contains($0.key) })
        }
        return nil
    }
}
