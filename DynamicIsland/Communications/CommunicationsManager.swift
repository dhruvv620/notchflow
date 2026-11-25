// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let communicationsEnabled = Key<Bool>("communicationsEnabled", default: false)
    static let communicationNotificationApps = Key<[String]>("communicationNotificationApps", default: ["messages", "whatsapp"])
    static let communicationCallApps = Key<[String]>("communicationCallApps", default: ["faceTime", "phone", "whatsapp", "teams", "zoom"])
    static let communicationShowPreviews = Key<Bool>("communicationShowPreviews", default: true)
    static let communicationRespectFocus = Key<Bool>("communicationRespectFocus", default: true)
}

extension Notification.Name {
    static let notchTabExplicitSelection = Notification.Name("NotchFlow.TabExplicitSelection")
}

@MainActor
final class CommunicationsManager: ObservableObject {
    static let shared = CommunicationsManager()
    @Published private(set) var notifications: [CommunicationNotification] = []
    @Published private(set) var calls: [CommunicationCall] = []
    @Published private(set) var accessGranted = false
    @Published private(set) var statusText = "Communications is off"
    @Published var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var pendingCallActionIDs = Set<String>()
    @Published private(set) var latestNotification: CommunicationNotification?
    @Published private(set) var notificationDiagnostics = NotificationBridgeDiagnostics.off
    private let notificationBridge = NativeNotificationBridge()
    private let callBridge = NativeCallBridge()
    private let accessibilityPermission = AccessibilityPermissionStore.shared
    private var loop: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var generation = 0
    private var notificationIDs: [String] = []
    private var hiddenNotificationIDs = Set<String>()
    private var callLastSeen: [String: Date] = [:]
    private var endingCalls: [String: Date] = [:]
    private var answeringCalls: [String: Date] = [:]
    /// Calls found from microphone use: their mute is the Mac's microphone.
    private var systemMuteCallIDs = Set<String>()
    private var audioCallTitles: [CommunicationApp: String] = [:]
    /// What the last scan found, for Settings.
    @Published private(set) var detectionSummary = "No call right now"

    var priorityCall: CommunicationCall? { CommunicationsPolicy.priorityCall(calls) }
    var enabled: Bool { Defaults[.communicationsEnabled] }

    private init() {
        var changes: [AnyPublisher<Bool, Never>] = []
        changes.append(Defaults.publisher(.communicationsEnabled, options: []).map { _ in true }.eraseToAnyPublisher())
        changes.append(Defaults.publisher(.communicationNotificationApps, options: []).map { _ in true }.eraseToAnyPublisher())
        changes.append(Defaults.publisher(.communicationCallApps, options: []).map { _ in true }.eraseToAnyPublisher())
        Publishers.MergeMany(changes).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        accessibilityPermission.$isAuthorized
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in self?.applyAccessStatus(granted) }
            .store(in: &subscriptions)
        configure()
    }

    func refreshAccess() {
        accessibilityPermission.refreshStatus()
        applyAccessStatus(accessibilityPermission.isAuthorized)
    }

    private func applyAccessStatus(_ granted: Bool) {
        let revoked = accessGranted && !granted
        if accessGranted != granted { accessGranted = granted }
        if revoked {
            generation += 1
            calls = []; latestNotification = nil; alertTask?.cancel()
            notifications = notifications.map { item in
                var copy = item; copy.canReply = false; copy.canOpen = false; copy.canDismiss = false
                return copy
            }
            Task { await notificationBridge.stop(); await callBridge.stop() }
        }
        if !enabled {
            notificationDiagnostics = .off
        } else if !granted {
            notificationDiagnostics = NotificationBridgeDiagnostics(
                state: .permissionRequired, processCount: 0, windowCount: 0,
                candidateCount: 0, recognizedCount: 0
            )
        }
        let text = !enabled ? "Communications is off" : (granted ? "Watching exposed notifications and call controls" : "Accessibility access is required")
        if statusText != text { statusText = text }
    }
    func requestAccess() {
        accessibilityPermission.requestAuthorizationPrompt()
        refreshAccess()
    }
    private var windowWatcher: NotificationCenterWindowWatcher?

    private func configure() {
        generation += 1
        loop?.cancel(); loop = nil
        refreshAccess()
        if !enabled {
            notifications = []; calls = []; latestNotification = nil
            notificationDiagnostics = .off
            notificationIDs = []; hiddenNotificationIDs = []; callLastSeen = [:]; endingCalls = [:]; answeringCalls = [:]
            alertTask?.cancel()
            Task { await notificationBridge.stop(); await callBridge.stop() }
            return
        }
        // A banner is read the moment Notification Center shows it; the scan
        // below is a slower backup (and catches banners that change in place).
        if windowWatcher == nil {
            windowWatcher = NotificationCenterWindowWatcher { [weak self] in
                guard let self, !EnergyState.isPaused(.bannerScan) else { return }
                Task { await self.refresh() }
            }
        } else {
            windowWatcher?.attach()
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Paced by the Optimizer; skipped while the Mac is idle.
                if !EnergyState.isPaused(.bannerScan) { await self.refresh() }
                try? await Task.sleep(for: .seconds(EnergyState.isPaused(.bannerScan) ? 5 : EnergyState.interval(.bannerScan)))
            }
        }
    }

    func refresh() async {
        refreshAccess()
        guard enabled, !isRefreshing, !LockScreenManager.shared.isLocked else { return }
        let version = generation
        isRefreshing = true
        defer { isRefreshing = false }
        let notificationApps = Set(Defaults[.communicationNotificationApps].compactMap(CommunicationApp.init(rawValue:)))
        let callApps = Set(Defaults[.communicationCallApps].compactMap(CommunicationApp.init(rawValue:)))
        // Calls are also found from microphone use, which needs no permission,
        // so a call shows even when its window's buttons can't be read.
        let audioApps = CallAudioPolicy.callApps(from: CallAudioMonitor.processes(), allowed: callApps,
                                                 ownBundleID: Bundle.main.bundleIdentifier ?? "")
        guard accessGranted else {
            guard version == generation else { return }
            await mergeCalls(observed: [], audioApps: audioApps, callApps: callApps)
            return
        }
        async let observedNotifications = notificationBridge.scan(allowedApps: notificationApps)
        async let observedCalls = callBridge.scan(allowedApps: callApps)
        let (notificationScan, observed) = await (observedNotifications, observedCalls)
        refreshAccess()
        guard enabled, version == generation, !Task.isCancelled else { return }
        notificationDiagnostics = notificationScan.diagnostics
        let capturedMessages = notificationScan.notifications
        hiddenNotificationIDs.formIntersection(Set(capturedMessages.map(\.id)))
        let messages = capturedMessages.filter { !hiddenNotificationIDs.contains($0.id) }
        // Older notifications seen while browsing the Notification Center panel aren't new.
        let newMessages = messages.filter { !notificationIDs.contains($0.id) && !$0.seenInPanel }
        let inbox = CommunicationsPolicy.mergeNotifications(existing: notifications, observed: messages,
                                                               allowedApps: notificationApps, limit: 20)
        if notifications != inbox { notifications = inbox }
        for message in newMessages {
            notificationIDs.append(message.id)
            if notificationIDs.count > 256 { notificationIDs.removeFirst(notificationIDs.count - 256) }
        }
        if let newest = newMessages.max(by: { $0.receivedAt < $1.receivedAt }), !(Defaults[.communicationRespectFocus] && DoNotDisturbManager.shared.isDoNotDisturbActive) {
            latestNotification = newest
            alertTask?.cancel()
            alertTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.latestNotification = nil
            }
        }
        await mergeCalls(observed: observed, audioApps: audioApps, callApps: callApps)
    }

    /// Combines calls read from their windows with calls found from microphone
    /// use, keeps a call through a brief gap, and frees the microphone after.
    private func mergeCalls(observed windowCalls: [CommunicationCall], audioApps: [CommunicationApp],
                            callApps: Set<CommunicationApp>) async {
        let now = Date()
        let micMuted = SystemMicrophone.shared.isMuted
        var observed = windowCalls
        var systemMuted = Set<String>()
        for index in observed.indices where observed[index].phase == .active
            && !observed[index].actions.contains(.mute) && !observed[index].actions.contains(.unmute) {
            observed[index].actions.insert(micMuted ? .unmute : .mute)
            systemMuted.insert(observed[index].id)
        }
        for app in audioApps where !observed.contains(where: { $0.app == app || (app == .faceTime && $0.app == .phone) }) {
            let id = "audio:\(app.rawValue)"
            if audioCallTitles[app] == nil, let title = await callBridge.callWindowTitle(app) { audioCallTitles[app] = title }
            let caller = audioCallTitles[app] ?? "\(app.title) call"
            var actions: Set<CommunicationCallAction> = [.open, micMuted ? .unmute : .mute]
            if accessGranted { actions.insert(.end) }
            observed.append(CommunicationCall(id: id, app: app, caller: caller, phase: .active, connectedAt: nil,
                                              observedAt: now, actions: actions))
            systemMuted.insert(id)
        }
        for app in audioCallTitles.keys where !audioApps.contains(app) { audioCallTitles.removeValue(forKey: app) }
        systemMuteCallIDs = systemMuted
        if observed.isEmpty {
            detectionSummary = "No call right now"
        } else {
            detectionSummary = observed.map { call in
                "\(call.app.title): \(call.id.hasPrefix("audio:") ? "found from microphone use" : "found in its window")"
            }.joined(separator: ", ")
        }

        let observedIDs = Set(observed.map(\.id))
        endingCalls = endingCalls.filter { observedIDs.contains($0.key) }
        var next: [CommunicationCall] = []
        for var call in observed {
            callLastSeen[call.id] = now
            if let previous = calls.first(where: { $0.id == call.id }) {
                call.observedAt = previous.observedAt
                call.connectedAt = call.connectedAt ?? previous.connectedAt
            }
            if let deadline = answeringCalls[call.id], deadline > now, call.phase == .incoming {
                call.phase = .connecting; call.actions = call.actions.intersection([.open])
            } else { answeringCalls.removeValue(forKey: call.id) }
            if let deadline = endingCalls[call.id] {
                if deadline > now { call.actions = call.actions.intersection([.open]) }
                else {
                    endingCalls.removeValue(forKey: call.id)
                    lastError = "The call is still present. Open \(call.app.title) to check its controls."
                }
            }
            next.append(call)
        }
        // A brief inaccessible AX tree during a transition must not end a call.
        // Retained cards lose action controls until positively observed again.
        for var previous in calls where !observedIDs.contains(previous.id) && callApps.contains(previous.app) {
            if observed.contains(where: { $0.app == previous.app && $0.caller == previous.caller }) { continue }
            if let seen = callLastSeen[previous.id], now.timeIntervalSince(seen) < 4 {
                previous.actions = [.open]; next.append(previous)
            } else { callLastSeen.removeValue(forKey: previous.id); answeringCalls.removeValue(forKey: previous.id) }
        }
        if calls != next { calls = next; MusicManager.shared.excludeCallPlaybackIfNeeded() }
        if next.isEmpty { SystemMicrophone.shared.releaseIfMutedByUs() }
    }

    func beginReply(id: String) async -> Bool {
        guard enabled, accessGranted, notifications.first(where: { $0.id == id })?.canReply == true else { return false }
        do { try await notificationBridge.perform(.beginReply, id: id); return true }
        catch { lastError = error.localizedDescription; return false }
    }
    func sendReply(_ text: String, id: String) async -> Bool {
        guard enabled, accessGranted, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do { try await notificationBridge.perform(.sendReply(text), id: id); lastError = nil; await refresh(); return true }
        catch { lastError = error.localizedDescription; return false }
    }
    func openNotification(id: String) async {
        guard let item = notifications.first(where: { $0.id == id }) else { return }
        if enabled && accessGranted && item.canOpen {
            do { try await notificationBridge.perform(.open, id: id) }
            catch { lastError = error.localizedDescription }
        } else { openSource(item.app) }
    }
    func dismissNotification(id: String) async {
        if enabled && accessGranted && notifications.first(where: { $0.id == id })?.canDismiss == true {
            do { try await notificationBridge.perform(.dismiss, id: id) }
            catch { lastError = error.localizedDescription; return }
        }
        hiddenNotificationIDs.insert(id)
        notifications.removeAll { $0.id == id }
        if latestNotification?.id == id { latestNotification = nil }
    }
    /// A text report of what NotchFlow can see of call apps, for bug reports.
    func callDiagnosticReport() async -> String {
        var report = await callBridge.diagnosticReport(audio: CallAudioMonitor.processes())
        report += "\n\nRight now: \(detectionSummary)"
        report += "\nMicrophone muted: \(SystemMicrophone.shared.isMuted ? "yes" : "no")"
        return report
    }
    func clearHistory() { hiddenNotificationIDs.formUnion(notifications.map(\.id)); notifications = []; latestNotification = nil; alertTask?.cancel() }

    func performCall(_ action: CommunicationCallAction, id: String) async {
        guard enabled, let call = calls.first(where: { $0.id == id }), !pendingCallActionIDs.contains(id) else { return }
        if action == .open { openSource(call.app); return }
        guard call.actions.contains(action) else { return }
        pendingCallActionIDs.insert(id)
        defer { pendingCallActionIDs.remove(id) }
        // The Mac's microphone, for calls whose own mute button can't be pressed.
        if (action == .mute || action == .unmute) && systemMuteCallIDs.contains(id) {
            if SystemMicrophone.shared.setMuted(action == .mute) {
                lastError = nil
                if let index = calls.firstIndex(where: { $0.id == id }) {
                    calls[index].actions.remove(action)
                    calls[index].actions.insert(action == .mute ? .unmute : .mute)
                }
            } else {
                lastError = "Couldn't change the microphone. Use the mute button in \(call.app.title)."
            }
            return
        }
        // Calls found from microphone use end through the app's menu.
        if action == .end && id.hasPrefix("audio:") {
            if await callBridge.endViaMenu(call.app) {
                lastError = nil
                endingCalls[id] = Date().addingTimeInterval(5)
            } else {
                lastError = "Couldn't end it from here. Open \(call.app.title) to hang up."
            }
            return
        }
        guard accessGranted else { lastError = "Allow Accessibility (Settings › Notifications & Calls) to use this button."; return }
        do {
            try await callBridge.perform(action, id: id)
            lastError = nil
            if action == .decline || action == .end {
                endingCalls[id] = Date().addingTimeInterval(5)
                if let index = calls.firstIndex(where: { $0.id == id }) { calls[index].actions = call.actions.intersection([.open]) }
            } else if action == .answer {
                answeringCalls[id] = Date().addingTimeInterval(5)
                if let index = calls.firstIndex(where: { $0.id == id }) {
                    calls[index].phase = .connecting; calls[index].actions = call.actions.intersection([.open])
                }
            }
            await refresh()
        } catch { lastError = error.localizedDescription }
    }
    func openSource(_ app: CommunicationApp) {
        let identifiers = app.bundleIdentifiers + (app == .phone ? ["com.apple.FaceTime"] : [])
        for identifier in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()); return
            }
        }
        if app == .instagram, let url = URL(string: "https://www.instagram.com/direct/inbox/") { NSWorkspace.shared.open(url) }
        else { lastError = "Open \(app.title) to continue. This app could not be found on your Mac." }
    }
    func isCallMediaSource(_ bundleIdentifier: String) -> Bool {
        guard enabled else { return false }
        return calls.contains {
            $0.app.bundleIdentifiers.contains(bundleIdentifier)
                || ([CommunicationApp.faceTime, .phone].contains($0.app) && bundleIdentifier.lowercased().hasPrefix("com.apple.facetime"))
        }
    }
}
