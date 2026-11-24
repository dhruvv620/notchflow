// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit

/// Restarts NotchFlow: the running copy quits, and a small helper opens the
/// same app again once it has fully exited (so the two never overlap and the
/// copy you're running is the one that comes back).
enum AppRelauncher {
    @MainActor
    static func restart() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let app = Bundle.main.bundleURL.path
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, app]
        do {
            try helper.run()
        } catch {
            // Fall back to asking macOS for a second copy before quitting.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration, completionHandler: nil)
        }
        NSApp.terminate(nil)
    }
}
