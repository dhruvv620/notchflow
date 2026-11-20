// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit

/// Offers to move NotchFlow into Applications when it was opened straight
/// from the disk image or a download. Run from there, macOS can't reopen it
/// after "Quit & Reopen" (granting Screen Recording, for example), it isn't
/// in Applications or Launchpad, and updates can't replace it.
@MainActor
enum AppLocationMover {
    /// Returns true when NotchFlow is quitting to reopen from Applications.
    static func moveIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let location = AppLocationPolicy.location(of: bundle.path, home: home)
        guard AppLocationPolicy.shouldOfferMove(location) else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move NotchFlow to your Applications folder?"
        alert.informativeText = "NotchFlow is running from \(describe(location)). Moved to Applications, it stays installed, reopens after you grant permissions, and gets updates."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let folder = AppLocationPolicy.destinationFolder(
            applicationsWritable: FileManager.default.isWritableFile(atPath: "/Applications"), home: home)
        let destination = URL(fileURLWithPath: folder).appendingPathComponent("NotchFlow.app")
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                // An older copy goes to the Trash, not away for good.
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundle, to: destination)
        } catch {
            let failed = NSAlert()
            failed.messageText = "NotchFlow couldn't move itself"
            failed.informativeText = "Drag NotchFlow into the Applications folder in Finder, then open it from there.\n\n\(error.localizedDescription)"
            failed.runModal()
            return false
        }
        // The download flag would make macOS ask again (or open a temporary copy).
        run("/usr/bin/xattr", ["-cr", destination.path])
        run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", destination.path])

        var eject: String?
        if case .diskImage(let volume) = location { eject = volume }
        let script = AppLocationPolicy.relaunchScript(pid: ProcessInfo.processInfo.processIdentifier,
                                                      newApp: destination.path, ejectVolume: eject)
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", script]
        do { try relaunch.run() } catch {
            NSWorkspace.shared.open(destination)
        }
        NSApp.terminate(nil)
        return true
    }

    private static func describe(_ location: AppLocationPolicy.Location) -> String {
        switch location {
        case .diskImage: return "the disk image it came in"
        case .translocated: return "a temporary copy macOS made of the download"
        default: return "outside the Applications folder"
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
