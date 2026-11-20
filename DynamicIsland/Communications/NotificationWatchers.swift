// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices
import Foundation

/// Calls back when a file changes (written, extended, replaced), so a reader
/// can look right away instead of on its next timer tick. Watches the file
/// and, when the file is replaced (SQLite's write-ahead log is recreated),
/// starts watching the new one.
@MainActor
final class FileChangeWatcher {
    private let urls: [URL]
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var rearm: DispatchWorkItem?

    init(urls: [URL], onChange: @escaping () -> Void) {
        self.urls = urls
        self.onChange = onChange
        arm()
    }

    deinit {
        sources.forEach { $0.cancel() }
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources = []
        for url in urls {
            // O_EVTONLY: watch without keeping the file busy. Needs read access
            // (Full Disk Access for Notification Center's store).
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                                   eventMask: [.write, .extend, .delete, .rename],
                                                                   queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let event = source.data
                MainActor.assumeIsolated {
                    if event.contains(.delete) || event.contains(.rename) { self.scheduleRearm() }
                    self.fire()
                }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
        // A file that didn't exist yet (no write-ahead log right now) is tried again later.
        if sources.count < urls.count { scheduleRearm(after: 10) }
    }

    /// Several writes in a row make one callback, a moment after the last.
    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func scheduleRearm(after delay: TimeInterval = 0.3) {
        rearm?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.arm() }
        rearm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Calls back the moment Notification Center puts up or takes down a window
/// (a banner appearing), through Accessibility notifications instead of
/// scanning on a timer.
@MainActor
final class NotificationCenterWindowWatcher {
    private var observer: AXObserver?
    private var element: AXUIElement?
    private var pid: pid_t = 0
    private let onChange: () -> Void
    private var pending: DispatchWorkItem?
    private var launchWatch: NSObjectProtocol?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        attach()
        // Notification Center can restart (after a crash or a login); follow it.
        launchWatch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                    == "com.apple.notificationcenterui" else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
    }

    deinit {
        if let launchWatch { NSWorkspace.shared.notificationCenter.removeObserver(launchWatch) }
    }

    func attach() {
        detach()
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return }
        pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationCenterWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.fire() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification,
                     kAXCreatedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        self.element = element
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        element = nil
    }

    /// A banner sliding in sends several notifications; read once it has settled.
    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
