// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import AppKit
import ApplicationServices
import Foundation

/// Conditional integration with exposed native call UI. AX references stay on
/// one serial worker; only immutable observations cross to the UI thread.
final class NativeCallBridge: @unchecked Sendable {
    private struct ProcessInfo: Sendable {
        let pid: pid_t
        let bundle: String
        let source: CommunicationApp?
    }
    private struct Record {
        let call: CommunicationCall
        let pid: pid_t
        let bundle: String
        let scope: AXUIElement
        let window: AXUIElement
        let capturedAt: Date
    }
    private struct Candidate {
        let source: CommunicationApp
        let scopeIndex: Int
        let indices: [Int]
        let match: CallClassificationPolicy.Match
        let controls: [Int]
        let context: String
    }
    private let queue = DispatchQueue(label: "com.dhruvv620.NotchFlow.call-accessibility", qos: .utility)
    private var records: [String: Record] = [:]
    private var firstSeen: [String: (first: Date, latest: Date)] = [:]
    private var rotation = 0

    func scan(allowedApps: Set<CommunicationApp>) async -> [CommunicationCall] {
        guard !allowedApps.isEmpty, AXIsProcessTrusted() else { await stop(); return [] }
        let processes: [ProcessInfo] = await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard let bundle = app.bundleIdentifier else { return nil }
                if bundle == "com.apple.notificationcenterui" {
                    return ProcessInfo(pid: app.processIdentifier, bundle: bundle, source: nil)
                }
                let source = Self.source(for: bundle)
                guard let source, allowedApps.contains(source) || (source == .faceTime && allowedApps.contains(.phone)) else { return nil }
                return ProcessInfo(pid: app.processIdentifier, bundle: bundle, source: source)
            }
        }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.collect(processes, allowed: allowedApps)) }
        }
    }

    func perform(_ action: CommunicationCallAction, id: String) async throws {
        let request: Record = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let record = self.records[id], Date().timeIntervalSince(record.capturedAt) <= 4 else {
                    continuation.resume(throwing: CommunicationActionError.expired); return
                }
                continuation.resume(returning: record)
            }
        }
        let stillRunning = await MainActor.run {
            NSRunningApplication(processIdentifier: request.pid)?.bundleIdentifier == request.bundle
        }
        guard stillRunning else { throw CommunicationActionError.expired }
        if action == .open {
            let opened = await MainActor.run { Self.open(request.call.app) }
            if !opened { throw CommunicationActionError.unavailable }
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                // Rescan this exact live scope and reclassify before every press.
                // A cached button can otherwise belong to a completed/replaced call.
                guard let current = self.records[id], current.pid == request.pid,
                      Date().timeIntervalSince(current.capturedAt) <= 4 else {
                    continuation.resume(throwing: CommunicationActionError.expired); return
                }
                let nodes = CommunicationsAX.snapshot(current.scope, maxNodes: 160, budget: 0.2)
                let controlIndices = Self.controlIndices(nodes)
                let controls = controlIndices.map { Self.control(nodes[$0]) }
                let context = nodes.flatMap(\.labels).joined(separator: " ")
                let liveSource = Self.contextSource(Self.source(for: current.bundle), context: context, nodes: nodes)
                guard liveSource == current.call.app,
                      let match = CallClassificationPolicy.classify(app: current.call.app, context: context, controls: controls),
                      Self.caller(in: nodes, windowTitle: CommunicationsAX.string(current.window, kAXTitleAttribute) ?? "",
                                  app: current.call.app, phase: match.phase) == current.call.caller,
                      let index = match.actions[action], controlIndices.indices.contains(index) else {
                    continuation.resume(throwing: CommunicationActionError.expired); return
                }
                let target = nodes[controlIndices[index]].element
                var pid: pid_t = 0
                guard AXUIElementGetPid(target, &pid) == .success, pid == current.pid,
                      CommunicationsAX.press(target) else {
                    continuation.resume(throwing: CommunicationActionError.failed("The call control did not respond. Open the call app to continue.")); return
                }
                continuation.resume()
            }
        }
    }

    /// Ends a call through the app's menu bar ("End Call", "Hang Up", "Leave
    /// Meeting"), for calls whose window buttons can't be read.
    func endViaMenu(_ app: CommunicationApp) async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let pids = await MainActor.run { Self.pids(for: app) }
        return await withCheckedContinuation { continuation in
            queue.async {
                for pid in pids {
                    let root = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(root, 0.2)
                    if let item = Self.menuItems(root).first(where: { CallAudioPolicy.isEndMenuTitle($0.title) && $0.enabled }),
                       AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success {
                        continuation.resume(returning: true); return
                    }
                }
                continuation.resume(returning: false)
            }
        }
    }

    /// The call window's title (usually who you're talking to), if readable.
    func callWindowTitle(_ app: CommunicationApp) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let pids = await MainActor.run { Self.pids(for: app) }
        return await withCheckedContinuation { continuation in
            queue.async {
                let ignored = Set([app.title.lowercased(), "facetime", "whatsapp", "zoom", "zoom workplace", "microsoft teams",
                                   "teams", "zoom meeting", "meeting", ""])
                for pid in pids {
                    let root = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(root, 0.1)
                    for window in CommunicationsAX.elements(root, kAXWindowsAttribute).prefix(4) {
                        let title = (CommunicationsAX.string(window, kAXTitleAttribute) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !ignored.contains(title.lowercased()), title.count <= 60 {
                            continuation.resume(returning: title); return
                        }
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    /// What NotchFlow can see of the call apps, for a bug report: button and
    /// menu labels only, never message text or window contents.
    func diagnosticReport(audio: [CallAudioPolicy.Process]) async -> String {
        var lines = ["NotchFlow call report", "Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not allowed")", ""]
        lines.append("Apps using the microphone:")
        if audio.isEmpty { lines.append("  none") }
        for process in audio {
            let app = CallAudioPolicy.app(for: process)?.title ?? "not a call app"
            lines.append("  \(process.name.isEmpty ? "?" : process.name) [\(process.bundleID)] input:\(process.input) output:\(process.output) -> \(app)")
        }
        guard AXIsProcessTrusted() else { return lines.joined(separator: "\n") }
        let targets: [(CommunicationApp, [pid_t])] = await MainActor.run {
            [CommunicationApp.faceTime, .whatsapp, .zoom, .teams].map { ($0, Self.pids(for: $0)) }
        }
        let body: [String] = await withCheckedContinuation { continuation in
            queue.async {
                var out: [String] = []
                for (app, pids) in targets where !pids.isEmpty {
                    out.append("")
                    out.append("\(app.title):")
                    for pid in pids {
                        let root = AXUIElementCreateApplication(pid)
                        AXUIElementSetMessagingTimeout(root, 0.1)
                        let windows = CommunicationsAX.elements(root, kAXWindowsAttribute)
                        out.append("  windows: \(windows.count)")
                        for (index, window) in windows.prefix(4).enumerated() {
                            let nodes = CommunicationsAX.snapshot(window, maxDepth: 9, maxNodes: 220, budget: 0.4)
                            let buttons = nodes.filter { Self.isControl($0) }.map { node in
                                "\(node.labels.isEmpty ? "(no label)" : node.labels.joined(separator: " / "))\(node.isEnabled ? "" : " [off]")"
                            }
                            out.append("  window \(index + 1) buttons: \(buttons.prefix(40).joined(separator: " | "))")
                        }
                        let menu = Self.menuItems(root).map(\.title).filter { title in
                            let text = title.lowercased()
                            return ["end", "hang", "leave", "mute", "microphone", "camera", "video", "call"].contains { text.contains($0) }
                        }
                        out.append("  call menu items: \(menu.isEmpty ? "none" : menu.joined(separator: " | "))")
                    }
                }
                continuation.resume(returning: out)
            }
        }
        return (lines + body).joined(separator: "\n")
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { self.records.removeAll(); self.firstSeen.removeAll(); continuation.resume() }
        }
    }

    private func collect(_ processes: [ProcessInfo], allowed: Set<CommunicationApp>) -> [CommunicationCall] {
        let now = Date()
        let deadline = now.addingTimeInterval(1.2)
        var next: [String: Record] = [:]
        let notifications = processes.filter { $0.source == nil }
        let apps = processes.filter { $0.source != nil }
        let rotated: [ProcessInfo]
        if apps.isEmpty { rotated = [] } else {
            let offset = rotation % apps.count
            rotated = Array(apps[offset...]) + Array(apps[..<offset])
            rotation += 1
        }
        for process in notifications + rotated where Date() < deadline {
            let root = AXUIElementCreateApplication(process.pid)
            AXUIElementSetMessagingTimeout(root, 0.05)
            let visibleRects = CommunicationsAX.onScreenWindowRects(pid: process.pid)
            if process.source == nil && visibleRects.isEmpty { continue }
            let windows = CommunicationsAX.elements(root, kAXWindowsAttribute)
            for window in windows.prefix(6) where Date() < deadline {
                let minimized = process.source != nil && CommunicationsAX.boolean(window, kAXMinimizedAttribute) == true
                guard minimized || CommunicationsAX.isOnScreen(window, windowRects: visibleRects) else { continue }
                let budget = min(0.22, max(0, deadline.timeIntervalSinceNow))
                let nodes = CommunicationsAX.snapshot(window, maxDepth: 9, maxNodes: 220, budget: budget)
                guard !nodes.isEmpty else { continue }
                var candidates: [Candidate] = []
                for index in nodes.indices where [kAXWindowRole, kAXGroupRole, kAXSheetRole, "AXDialog"].contains(nodes[index].role) {
                    let indices = Self.descendants(of: index, nodes: nodes)
                    guard indices.count >= 3 else { continue }
                    let context = indices.flatMap { nodes[$0].labels }.joined(separator: " ")
                    guard let source = Self.contextSource(process.source, context: context, nodes: indices.map { nodes[$0] }),
                          allowed.contains(source) else { continue }
                    let controls = indices.filter { Self.isControl(nodes[$0]) }
                    let descriptors = controls.map { Self.control(nodes[$0]) }
                    guard let match = CallClassificationPolicy.classify(app: source, context: context, controls: descriptors),
                          (minimized || CommunicationsAX.isOnScreen(nodes[index].element, windowRects: visibleRects)) else { continue }
                    candidates.append(Candidate(source: source, scopeIndex: index, indices: indices,
                                                match: match, controls: controls, context: context))
                }
                // A narrow card/dialog wins over its whole-window ancestors.
                var accepted = Set<Int>()
                for candidate in candidates.sorted(by: { $0.indices.count < $1.indices.count }) {
                    guard accepted.isDisjoint(with: candidate.indices) else { continue }
                    accepted.formUnion(candidate.indices)
                    let scope = nodes[candidate.scopeIndex]
                    let caller = Self.caller(in: candidate.indices.map { nodes[$0] }, windowTitle: nodes[0].title, app: candidate.source,
                                             phase: candidate.match.phase)
                    let id = "call:\(process.pid):\(candidate.source.rawValue):\(CFHash(scope.element)):\(caller)"
                    let first = firstSeen[id]?.first ?? now
                    firstSeen[id] = (first, now)
                    var actions = Set(candidate.match.actions.keys)
                    actions.insert(.open)
                    let call = CommunicationCall(id: id, app: candidate.source, caller: caller, phase: candidate.match.phase,
                                                 connectedAt: nil, observedAt: first, actions: actions)
                    next[id] = Record(call: call, pid: process.pid, bundle: process.bundle, scope: scope.element, window: window, capturedAt: now)
                }
            }
        }
        records = next
        firstSeen = firstSeen.filter { now.timeIntervalSince($0.value.latest) < 6 }
        return next.values.map(\.call).sorted {
            let left = Self.priority($0.phase), right = Self.priority($1.phase)
            return left == right ? $0.observedAt < $1.observedAt : left < right
        }
    }

    @MainActor private static func pids(for app: CommunicationApp) -> [pid_t] {
        NSWorkspace.shared.runningApplications.filter { running in
            guard let bundle = running.bundleIdentifier else { return false }
            return app.bundleIdentifiers.contains(bundle)
                || ((app == .faceTime || app == .phone) && bundle.lowercased().hasPrefix("com.apple.facetime"))
        }.map(\.processIdentifier)
    }

    private struct MenuItem { let element: AXUIElement; let title: String; let enabled: Bool }

    /// Every item of an app's menu bar menus (one level of submenus).
    private static func menuItems(_ root: AXUIElement) -> [MenuItem] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return [] }
        let bar = value as! AXUIElement
        var items: [MenuItem] = []
        func collect(_ menu: AXUIElement, depth: Int) {
            for item in CommunicationsAX.elements(menu, kAXChildrenAttribute).prefix(60) {
                let title = CommunicationsAX.string(item, kAXTitleAttribute) ?? ""
                if !title.isEmpty { items.append(MenuItem(element: item, title: title, enabled: CommunicationsAX.enabled(item))) }
                if depth < 1 {
                    for submenu in CommunicationsAX.elements(item, kAXChildrenAttribute).prefix(1) { collect(submenu, depth: depth + 1) }
                }
            }
        }
        for barItem in CommunicationsAX.elements(bar, kAXChildrenAttribute).dropFirst().prefix(12) {
            for menu in CommunicationsAX.elements(barItem, kAXChildrenAttribute).prefix(1) { collect(menu, depth: 0) }
        }
        return items
    }

    private static func source(for bundle: String) -> CommunicationApp? {
        if ["com.apple.FaceTime.FaceTimeNotificationCenterService", "com.apple.FaceTime.FTCallUIService",
            "com.apple.facetime.FTCallUIService"].contains(bundle) { return .faceTime }
        return CommunicationApp.allCases.first { [.faceTime, .phone, .whatsapp, .teams, .zoom].contains($0) && $0.bundleIdentifiers.contains(bundle) }
    }
    private static func contextSource(_ processSource: CommunicationApp?, context: String, nodes: [CommunicationsAX.Node]) -> CommunicationApp? {
        if let processSource {
            if processSource == .faceTime && context.lowercased().contains("iphone") { return .phone }
            return processSource
        }
        // Notification Center is shared by every app. Only an explicit app label
        // in the same card can authorize controls; message contents never do.
        let labels = Set(nodes.filter { $0.role == kAXStaticTextRole }.flatMap(\.labels).map(CallClassificationPolicy.normalized))
        let headers = nodes.filter { $0.role == kAXStaticTextRole }.compactMap { node in
            [node.value, node.title, node.description].first { !$0.isEmpty }
        }
        guard let header = headers.first, NotificationCardPolicy.app(named: header) != nil else { return nil }
        var sources = Set<CommunicationApp>()
        if labels.contains("facetime") { sources.insert(.faceTime) }
        if labels.contains("phone") || labels.contains("calls from iphone") { sources.insert(.phone) }
        if labels.contains("whatsapp") { sources.insert(.whatsapp) }
        if labels.contains("microsoft teams") || labels.contains("teams") { sources.insert(.teams) }
        if labels.contains("zoom") || labels.contains("zoom workplace") { sources.insert(.zoom) }
        return sources.count == 1 ? sources.first : nil
    }
    private static func isControl(_ node: CommunicationsAX.Node) -> Bool {
        [kAXButtonRole, kAXCheckBoxRole, "AXToggleButton"].contains(node.role)
    }
    private static func controlIndices(_ nodes: [CommunicationsAX.Node]) -> [Int] { nodes.indices.filter { isControl(nodes[$0]) } }
    private static func control(_ node: CommunicationsAX.Node) -> CallClassificationPolicy.Control {
        .init(labels: node.labels, enabled: node.isEnabled, pressable: node.actionNames.contains(kAXPressAction))
    }
    private static func descendants(of ancestor: Int, nodes: [CommunicationsAX.Node]) -> [Int] {
        nodes.indices.filter { index in
            if index == ancestor { return true }
            var current = nodes[index].parentIndex
            while let parent = current {
                if parent == ancestor { return true }
                current = nodes[parent].parentIndex
            }
            return false
        }
    }
    private static func caller(in nodes: [CommunicationsAX.Node], windowTitle: String, app: CommunicationApp,
                               phase: CommunicationCallPhase) -> String {
        let ignored = Set([app.title.lowercased(), "facetime", "phone", "whatsapp", "microsoft teams", "teams", "zoom", "zoom workplace", "notification center", "notificationcenter"])
        let text = nodes.filter { $0.role == kAXStaticTextRole }.flatMap(\.labels) + [windowTitle]
        for raw in text {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = value.lowercased()
            guard value.count > 1, value.count <= 90, !ignored.contains(normalized), !value.contains("\n"),
                  !["call", "meeting", "connecting", "ringing", "mute", "camera", "answer", "decline"].contains(where: { normalized.contains($0) }),
                  value.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) == nil else { continue }
            return value
        }
        return phase == .incoming ? "Incoming call" : "Call in progress"
    }
    private static func priority(_ phase: CommunicationCallPhase) -> Int {
        switch phase { case .incoming: return 0; case .connecting: return 1; case .active: return 2 }
    }
    @MainActor private static func open(_ app: CommunicationApp) -> Bool {
        if let running = NSWorkspace.shared.runningApplications.first(where: { app.bundleIdentifiers.contains($0.bundleIdentifier ?? "") }) {
            return running.activate(options: .activateIgnoringOtherApps)
        }
        guard let url = app.bundleIdentifiers.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return true
    }
}
