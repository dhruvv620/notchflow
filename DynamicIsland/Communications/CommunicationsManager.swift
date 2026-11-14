// SPDX-License-Identifier: GPL-3.0-or-later
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
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func refresh() async {
        refreshAccess()
        guard enabled, accessGranted, !isRefreshing, !LockScreenManager.shared.isLocked else { return }
        let version = generation
        isRefreshing = true
        defer { isRefreshing = false }
        let notificationApps = Set(Defaults[.communicationNotificationApps].compactMap(CommunicationApp.init(rawValue:)))
        let callApps = Set(Defaults[.communicationCallApps].compactMap(CommunicationApp.init(rawValue:)))
        async let observedNotifications = notificationBridge.scan(allowedApps: notificationApps)
        async let observedCalls = callBridge.scan(allowedApps: callApps)
        let (notificationScan, observed) = await (observedNotifications, observedCalls)
        refreshAccess()
        guard enabled, accessGranted, version == generation, !Task.isCancelled else { return }
        notificationDiagnostics = notificationScan.diagnostics
        let capturedMessages = notificationScan.notifications
        let now = Date()
        hiddenNotificationIDs.formIntersection(Set(capturedMessages.map(\.id)))
        let messages = capturedMessages.filter { !hiddenNotificationIDs.contains($0.id) }
        let newMessages = messages.filter { !notificationIDs.contains($0.id) }
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
    func clearHistory() { hiddenNotificationIDs.formUnion(notifications.map(\.id)); notifications = []; latestNotification = nil; alertTask?.cancel() }

    func performCall(_ action: CommunicationCallAction, id: String) async {
        guard enabled, accessGranted, let call = calls.first(where: { $0.id == id }), !pendingCallActionIDs.contains(id) else { return }
        if action == .open { openSource(call.app); return }
        guard call.actions.contains(action) else { return }
        pendingCallActionIDs.insert(id)
        defer { pendingCallActionIDs.remove(id) }
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
        guard enabled, accessGranted else { return false }
        return calls.contains {
            $0.app.bundleIdentifiers.contains(bundleIdentifier)
                || ([CommunicationApp.faceTime, .phone].contains($0.app) && bundleIdentifier.lowercased().hasPrefix("com.apple.facetime"))
        }
    }
}
