// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct AppLocationRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "AppLocationRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = AppLocationPolicy
        let home = "/Users/riya"
        try require(P.location(of: "/Applications/NotchFlow.app", home: home) == .applications, "Applications")
        try require(P.location(of: "/Users/riya/Applications/NotchFlow.app", home: home) == .applications, "Home Applications")
        try require(P.location(of: "/Volumes/NotchFlow 1.2.0/NotchFlow.app", home: home) == .diskImage(volume: "/Volumes/NotchFlow 1.2.0"), "Disk image")
        try require(P.location(of: "/private/var/folders/x1/abc/T/AppTranslocation/4F2C/d/NotchFlow.app", home: home) == .translocated, "Translocated")
        try require(P.location(of: "/Users/riya/Downloads/NotchFlow.app", home: home) == .elsewhere, "Downloads")
        try require(P.location(of: "/Users/me/Library/Caches/NotchFlowFresh/Build/Products/Release/NotchFlow.app", home: "/Users/me") == .development, "Dev build")
        try require(!P.shouldOfferMove(.applications) && !P.shouldOfferMove(.development), "Offered a move from Applications or a dev build")
        try require(P.shouldOfferMove(.diskImage(volume: "/Volumes/X")) && P.shouldOfferMove(.translocated) && P.shouldOfferMove(.elsewhere), "Didn't offer a move")
        try require(P.destinationFolder(applicationsWritable: true, home: home) == "/Applications"
                    && P.destinationFolder(applicationsWritable: false, home: home) == "/Users/riya/Applications", "Destination")
        let script = P.relaunchScript(pid: 42, newApp: "/Applications/NotchFlow.app", ejectVolume: "/Volumes/NotchFlow 1.2.0")
        try require(script == "while /bin/kill -0 42 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open '/Applications/NotchFlow.app'; /usr/bin/hdiutil detach '/Volumes/NotchFlow 1.2.0' -quiet || true", "Script: \(script)")
        try require(P.relaunchScript(pid: 1, newApp: "/Users/o'neil/Applications/NotchFlow.app", ejectVolume: nil).contains("'/Users/o'\\''neil/Applications/NotchFlow.app'"), "Quote escaping")
        print("App location: OK")
    }
}
