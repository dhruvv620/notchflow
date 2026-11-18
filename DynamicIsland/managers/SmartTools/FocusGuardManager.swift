// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Defaults

extension Defaults.Keys {
    /// During a Pomodoro focus block, glow amber when a distracting site or app is in front.
    static let enableFocusGuard = Key<Bool>("enableFocusGuard", default: false)
    static let focusGuardSites = Key<String>("focusGuardSites", default: FocusGuardPolicy.defaultSites.joined(separator: ", "))
    static let focusGuardApps = Key<String>("focusGuardApps", default: "")
}

/// The distraction meter: while a Pomodoro focus block runs, checks the
/// front app (and, for browsers, the front tab's address) every few seconds
/// and counts the time spent on distracting sites and apps.
@MainActor
final class FocusGuardManager: ObservableObject {
    static let shared = FocusGuardManager()

    /// A distracting site or app is in front right now.
    @Published private(set) var isOffTrack = false
    /// Time off track in the current focus block.
    @Published private(set) var offTrackSeconds: TimeInterval = 0
    /// What is distracting: a host ("youtube.com") or an app name.
    @Published private(set) var source = ""

    static let browserScripts: [String: String] = [
        "com.apple.Safari": #"tell application id "com.apple.Safari" to return URL of front document"#,
        "com.google.Chrome": #"tell application id "com.google.Chrome" to return URL of active tab of front window"#,
        "company.thebrowser.Browser": #"tell application id "company.thebrowser.Browser" to return URL of active tab of front window"#,
        "com.brave.Browser": #"tell application id "com.brave.Browser" to return URL of active tab of front window"#,
        "com.microsoft.edgemac": #"tell application id "com.microsoft.edgemac" to return URL of active tab of front window"#,
    ]

    private var timer: AnyCancellable?
    private var lastTick: Date?
    private var wasInFocus = false
    private var isProbing = false
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.tick(now: now) }
    }

    private var isInFocusBlock: Bool {
        let pomodoro = TimerModesManager.shared.pomodoro
        return pomodoro.isActive && !pomodoro.isPaused && pomodoro.phase == .focus
    }

    private func tick(now: Date) {
        guard Defaults[.enableFocusGuard], isInFocusBlock else {
            if wasInFocus || isOffTrack || offTrackSeconds > 0 { reset() }
            return
        }
        if !wasInFocus {
            // A new focus block starts with a clean meter.
            wasInFocus = true
            offTrackSeconds = 0
            lastTick = now
        }
        guard !isProbing else { return }
        let elapsed = min(max(now.timeIntervalSince(lastTick ?? now), 0), 6)
        lastTick = now

        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            apply(distraction: nil, elapsed: elapsed)
            return
        }
        let bundleID = app.bundleIdentifier ?? ""
        let apps = FocusGuardPolicy.list(from: Defaults[.focusGuardApps])
        if FocusGuardPolicy.isDistracting(bundleID: bundleID, url: nil, apps: apps, sites: []) {
            apply(distraction: app.localizedName ?? bundleID, elapsed: elapsed)
            return
        }
        guard let script = Self.browserScripts[bundleID] else {
            apply(distraction: nil, elapsed: elapsed)
            return
        }
        isProbing = true
        Task { @MainActor [weak self] in
            let address = try? await AppleScriptHelper.execute(script)?.stringValue
            guard let self else { return }
            self.isProbing = false
            let sites = FocusGuardPolicy.list(from: Defaults[.focusGuardSites])
            let url = address.flatMap(URL.init(string:))
            let hit = FocusGuardPolicy.isDistracting(bundleID: nil, url: url, apps: [], sites: sites)
            self.apply(distraction: hit ? url?.host?.replacingOccurrences(of: "www.", with: "") : nil, elapsed: elapsed)
        }
    }

    private func apply(distraction: String?, elapsed: TimeInterval) {
        if let distraction {
            offTrackSeconds += elapsed
            if source != distraction { source = distraction }
            if !isOffTrack { isOffTrack = true }
        } else if isOffTrack {
            isOffTrack = false
        }
    }

    private func reset() {
        wasInFocus = false
        isOffTrack = false
        offTrackSeconds = 0
        source = ""
        lastTick = nil
    }
}
