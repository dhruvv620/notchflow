// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Where NotchFlow is running from, and whether it should offer to move
/// itself into Applications (Foundation only, so Build.command can check it alone).
enum AppLocationPolicy {
    enum Location: Equatable {
        /// /Applications or ~/Applications.
        case applications
        /// Opened straight from the disk image, e.g. "/Volumes/NotchFlow 1.2.0".
        case diskImage(volume: String)
        /// A read-only copy macOS makes for an app opened from a download.
        case translocated
        /// Downloads, Desktop or another folder.
        case elsewhere
        /// A development build (Xcode, Build.command's cache).
        case development
    }

    static func location(of bundlePath: String, home: String) -> Location {
        let path = (bundlePath as NSString).standardizingPath
        let homeApps = (home as NSString).appendingPathComponent("Applications")
        if path.hasPrefix("/Applications/") || path.hasPrefix(homeApps + "/") { return .applications }
        if path.contains("/AppTranslocation/") { return .translocated }
        if path.hasPrefix("/Volumes/") {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            return parts.count >= 2 ? .diskImage(volume: "/" + parts[0...1].joined(separator: "/")) : .elsewhere
        }
        if path.contains("/DerivedData/") || path.contains("/Library/Caches/NotchFlow") || path.contains("/Build/Products/") {
            return .development
        }
        return .elsewhere
    }

    /// Whether to offer moving: anywhere but Applications or a development build.
    static func shouldOfferMove(_ location: Location) -> Bool {
        switch location {
        case .applications, .development: return false
        case .diskImage, .translocated, .elsewhere: return true
        }
    }

    /// /Applications when it can be written to (admin accounts), otherwise ~/Applications.
    static func destinationFolder(applicationsWritable: Bool, home: String) -> String {
        applicationsWritable ? "/Applications" : (home as NSString).appendingPathComponent("Applications")
    }

    /// A shell script that waits for this copy to quit, opens the moved one,
    /// and ejects the disk image it came from.
    static func relaunchScript(pid: Int32, newApp: String, ejectVolume: String?) -> String {
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(quoted(newApp))"
        if let ejectVolume { script += "; /usr/bin/hdiutil detach \(quoted(ejectVolume)) -quiet || true" }
        return script
    }
}
