// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import Foundation

/// Finds calls from which apps are using the microphone and speakers, so a
/// call shows in the notch even when its window's buttons can't be read.
/// Both input and output must be running: a voice note or dictation uses only
/// the microphone, a call uses both.
enum CallAudioPolicy {
    struct Process: Equatable, Sendable {
        let pid: Int32
        let bundleID: String
        let name: String
        let input: Bool
        let output: Bool
    }

    /// FaceTime and iPhone calls run their audio in these system processes.
    static let faceTimeProcesses: Set<String> = ["avconferenced", "callservicesd", "facetime", "ftcalluiservice"]

    static func app(for process: Process) -> CommunicationApp? {
        let bundle = process.bundleID.lowercased()
        let name = process.name.lowercased()
        if bundle.contains("facetime") || bundle.contains("avconference") || bundle.contains("callservices")
            || faceTimeProcesses.contains(name) { return .faceTime }
        for app in [CommunicationApp.whatsapp, .zoom, .teams] {
            if app.bundleIdentifiers.contains(where: { bundle.hasPrefix($0.lowercased()) }) { return app }
        }
        if name == "zoom.us" || name == "cpthost" { return .zoom }
        if name.hasPrefix("microsoft teams") || name.hasPrefix("msteams") { return .teams }
        if name == "whatsapp" { return .whatsapp }
        return nil
    }

    /// The call apps with a call going on right now.
    static func callApps(from processes: [Process], allowed: Set<CommunicationApp>, ownBundleID: String) -> [CommunicationApp] {
        var result: [CommunicationApp] = []
        for process in processes where process.input && process.output && process.bundleID != ownBundleID {
            guard let app = app(for: process) else { continue }
            let permitted = allowed.contains(app) || (app == .faceTime && allowed.contains(.phone))
            if permitted && !result.contains(app) { result.append(app) }
        }
        return result
    }

    /// Menu items that end a call, in the order to try them.
    static func isEndMenuTitle(_ title: String) -> Bool {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "…", with: "")
        if text.contains("for all") || text.contains("for everyone") { return false }
        return ["end call", "end", "hang up", "leave call", "leave meeting", "leave", "end video call",
                "end audio call", "end voice call"].contains(text)
    }
}
