// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Read delivered notifications from Notification Center's store (needs Full Disk Access).
    static let notificationReadCenterHistory = Key<Bool>("notificationReadCenterHistory", default: true)
    /// Announce new notifications in the closed notch.
    static let notificationAlertInNotch = Key<Bool>("notificationAlertInNotch", default: true)
    /// Bundle identifiers whose notifications are never collected.
    static let notificationMutedApps = Key<[String]>("notificationMutedApps", default: [])
    /// Highest Notification Center record already collected.
    static let notificationCenterLastRecordID = Key<Int>("notificationCenterLastRecordID", default: 0)
    /// When the Notifications tab was last looked at (seconds since 1970).
    static let notificationsLastViewedAt = Key<Double>("notificationsLastViewedAt", default: 0)
}

/// The notch's notification inbox.
///
/// Collects from three places and merges them into one list:
/// - Notification Center's own store, for every app, including notifications
///   whose banner was never seen (needs Full Disk Access);
/// - banners on screen, read through Accessibility, which add the native
///   Reply, Open and Close actions while the banner is still showing;
/// - the linked WhatsApp gateway, whose messages can always be answered.
///
/// The inbox is kept on this Mac between launches. Clearing it never touches
/// Notification Center itself.
@MainActor
final class NotificationHub: ObservableObject {
    static let shared = NotificationHub()

    enum CenterState: Equatable {
        case off
        case needsFullDiskAccess
        case notFound
        case unsupported(String)
        case reading
        case failed(String)

        var message: String {
            switch self {
            case .off: return "Notification Center history is off."
            case .needsFullDiskAccess: return "Allow Full Disk Access to collect every app's notifications, even ones whose banner you missed."
            case .notFound: return "Notification Center's store was not found on this Mac."
            case .unsupported(let detail): return "This macOS stores notifications in a layout NotchFlow does not read yet (\(detail))."
            case .reading: return "Collecting notifications from Notification Center."
            case .failed(let detail): return "Notification Center could not be read: \(detail)"
            }
        }
    }

    @Published private(set) var items: [NotchNotification] = []
    @Published private(set) var alert: NotchNotification?
    @Published private(set) var centerState: CenterState = .off
    /// A group key to show only one app, or nil for everything.
    @Published var filter: String?
    /// The notification whose reply field is open.
    @Published var replyingID: String?
    /// A notification to bring into view, e.g. the one just announced.
    @Published private(set) var highlightedID: String?
    private var highlightTask: Task<Void, Never>?
    @Published private(set) var sendingIDs: Set<String> = []
    @Published private(set) var repliedIDs: Set<String> = []
    @Published var lastError: String?
    /// What the last Clear removed, offered back for a few seconds.
    @Published private(set) var undoSnapshot: [NotchNotification]?

    var visibleItems: [NotchNotification] {
        guard let filter else { return items }
        return items.filter { $0.groupKey == filter }
    }
    var groups: [NotchNotificationGroup] { NotchNotificationPolicy.grouped(visibleItems) }
    var allGroups: [NotchNotificationGroup] { NotchNotificationPolicy.grouped(items) }

    /// Notifications that arrived since the tab was last on screen.
    var unseenCount: Int {
        let viewed = Defaults[.notificationsLastViewedAt]
        return items.filter { $0.date.timeIntervalSince1970 > viewed }.count
    }

    func markViewed() {
        Defaults[.notificationsLastViewedAt] = Date().timeIntervalSince1970
    }

    private static let historyLimit = 200
    private let database = NotificationCenterDatabase()
    private var loop: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var appNames: [String: String] = [:]
    private var started = false

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        items = Self.loadHistory()

        var changes: [AnyPublisher<Bool, Never>] = []
        changes.append(Defaults.publisher(.communicationsEnabled).map { _ in true }.eraseToAnyPublisher())
        changes.append(Defaults.publisher(.notificationReadCenterHistory, options: []).map { _ in true }.eraseToAnyPublisher())
        changes.append(FullDiskAccessPermissionStore.shared.$isAuthorized.removeDuplicates().map { _ in true }.eraseToAnyPublisher())
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.configure() }
            .store(in: &subscriptions)

        CommunicationsManager.shared.$notifications
            .receive(on: RunLoop.main)
            .sink { [weak self] banners in self?.ingestBanners(banners) }
            .store(in: &subscriptions)

        Defaults.publisher(.notificationMutedApps, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                let muted = Set(change.newValue)
                self.replaceItems(self.items.filter { !muted.contains($0.bundleIdentifier ?? "") })
            }
            .store(in: &subscriptions)
    }

    private var enabled: Bool { Defaults[.communicationsEnabled] }

    private func configure() {
        loop?.cancel()
        loop = nil
        guard enabled else {
            centerState = .off
            dismissAlert()
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Paced by the Optimizer; skipped while the Mac is idle.
                if !EnergyState.isPaused(.notificationDatabase) { await self.pollNotificationCenter() }
                try? await Task.sleep(for: .seconds(EnergyState.isPaused(.notificationDatabase) ? 5 : EnergyState.interval(.notificationDatabase)))
            }
        }
    }

    /// Re-reads Notification Center now, e.g. after Full Disk Access was granted.
    func refresh() async {
        FullDiskAccessPermissionStore.shared.refreshStatus()
        await pollNotificationCenter(force: true)
        await CommunicationsManager.shared.refresh()
    }

    // MARK: Notification Center store

    private func pollNotificationCenter(force: Bool = false) async {
        guard enabled, Defaults[.notificationReadCenterHistory] else {
            centerState = .off
            return
        }
        let last = Int64(Defaults[.notificationCenterLastRecordID])
        let isFirstRead = last == 0
        do {
            guard let batch = try await database.read(afterRecordID: last, limit: isFirstRead ? 40 : 100, force: force) else {
                if centerState != .reading { centerState = .reading }
                return
            }
            if centerState != .reading { centerState = .reading }
            // Record ids are reused when the newest rows are deleted, so a
            // lower maximum means the store was cleared: start over from it.
            let nextLast = batch.latestRecordID < last ? batch.latestRecordID : max(last, batch.latestRecordID)
            if Int(nextLast) != Defaults[.notificationCenterLastRecordID] {
                Defaults[.notificationCenterLastRecordID] = Int(nextLast)
            }
            let incoming = batch.records
                .filter { !isMuted($0.bundleIdentifier) }
                .map { $0.notification(appName: appName(for: $0.bundleIdentifier)) }
            // The first read fills the inbox quietly; later ones announce.
            add(incoming, announce: !isFirstRead)
        } catch let error as NotificationCenterDatabase.ReadError {
            switch error {
            case .permissionDenied: centerState = .needsFullDiskAccess
            case .notFound: centerState = .notFound
            case .unsupportedLayout(let detail): centerState = .unsupported(detail)
            case .sqlite(let detail): centerState = .failed(detail)
            }
        } catch {
            centerState = .failed(error.localizedDescription)
        }
    }

    // MARK: Other sources

    private func ingestBanners(_ banners: [CommunicationNotification]) {
        guard enabled else { return }
        let live = banners.filter { $0.canReply || $0.canOpen || $0.canDismiss }
        let liveIDs = Set(live.map(\.id))
        var next = items

        // Banners that left the screen lose their actions.
        for index in next.indices {
            if let banner = next[index].liveBannerID, !liveIDs.contains(banner) {
                next[index].liveBannerID = nil
                if case .banner = next[index].reply { next[index].reply = .none }
            }
        }

        var fresh: [NotchNotification] = []
        for banner in banners {
            let bundle = banner.app.bundleIdentifiers.first
            if isMuted(bundle) { continue }
            let isLive = liveIDs.contains(banner.id)
            let candidate = NotchNotification(
                id: "banner-\(banner.id)",
                source: .banner,
                bundleIdentifier: bundle,
                appName: banner.app.title,
                title: banner.sender,
                subtitle: "",
                body: banner.body,
                date: banner.receivedAt,
                threadID: nil,
                reply: (isLive && banner.canReply) ? .banner(id: banner.id) : .none,
                liveBannerID: isLive ? banner.id : nil
            )
            let window: TimeInterval = banner.seenInPanel ? .infinity : 90
            if let index = next.firstIndex(where: { NotchNotificationPolicy.isSameNotification(candidate, as: $0, window: window) }) {
                // Already collected from Notification Center: lend it the banner's actions.
                if isLive {
                    next[index].liveBannerID = banner.id
                    if !next[index].reply.isAvailable, banner.canReply { next[index].reply = .banner(id: banner.id) }
                }
            } else if let index = next.firstIndex(where: { $0.id == candidate.id }) {
                next[index].liveBannerID = candidate.liveBannerID
                if case .banner = next[index].reply, !isLive { next[index].reply = .none }
                if isLive, banner.canReply { next[index].reply = .banner(id: banner.id) }
            } else if !banner.seenInPanel {
                fresh.append(candidate)
            }
            // An older card seen while browsing the Notification Center panel
            // and not in the inbox stays out of it: it isn't new, and its time
            // on screen would show it as "now".
        }
        if next != items { replaceItems(next) }
        add(fresh, announce: true)
    }

    /// Called by the WhatsApp integration for each incoming message.
    func ingestWhatsApp(_ message: WhatsAppMessage, chatName: String, isGroup: Bool) {
        guard enabled, !message.isFromMe else { return }
        let sender = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = isGroup && !sender.isEmpty ? "\(sender) · \(chatName)" : chatName
        let item = NotchNotification(
            id: "wa-\(message.id)",
            source: .whatsapp,
            bundleIdentifier: "net.whatsapp.WhatsApp",
            appName: "WhatsApp",
            title: title,
            subtitle: "",
            body: message.previewText,
            date: message.timestamp,
            threadID: message.chatJID,
            reply: .whatsapp(chatJID: message.chatJID),
            liveBannerID: nil
        )
        // WhatsApp announces its own messages in the notch.
        add([item], announce: false)
    }

    // MARK: Inbox changes

    private func add(_ incoming: [NotchNotification], announce: Bool) {
        let known = Set(items.map(\.id))
        // A message the linked WhatsApp account already delivered, shown again
        // by the WhatsApp app on this Mac (when both are the same account).
        let new = incoming.filter { item in
            !known.contains(item.id)
                && !(item.source != .whatsapp && items.contains { NotchNotificationPolicy.isSameWhatsAppMessage(item, $0) })
        }
        guard !new.isEmpty else { return }
        // And the other way round: the linked account's copy replaces the Mac
        // app's, since it can be replied to from the notch.
        let gatewayMessages = new.filter { $0.source == .whatsapp }
        let remaining = gatewayMessages.isEmpty ? items : items.filter { existing in
            !gatewayMessages.contains { NotchNotificationPolicy.isSameWhatsAppMessage($0, existing) }
        }
        replaceItems(new + remaining)
        // Promises people make you in chat apps (WhatsApp is watched by its gateway).
        for item in new where item.source != .whatsapp && Self.promiseChatApps.contains(item.bundleIdentifier ?? "") {
            let route: TrackedPromise.Route
            if case .messages(let chat) = item.reply { route = .messages(chatID: chat) } else { route = .none }
            PromiseKeeper.shared.observe(text: item.body, fromMe: false, person: item.headline, route: route,
                                         sourceName: item.appName, at: item.date)
        }
        guard announce, let newest = new.max(by: { $0.date < $1.date }),
              Date().timeIntervalSince(newest.date) < 120 else { return }
        showAlert(newest)
    }

    /// Chat apps whose notifications are checked for promises made to you.
    private static let promiseChatApps: Set<String> = NotchNotificationPolicy.whatsAppBundleIdentifiers.union([
        NotchNotificationPolicy.messagesBundleIdentifier, "com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram",
        "com.hnc.Discord", "org.whispersystems.signal-desktop", "com.microsoft.teams2",
    ])

    private func replaceItems(_ next: [NotchNotification]) {
        let normalized = NotchNotificationPolicy.normalized(next, limit: Self.historyLimit)
        guard normalized != items else { return }
        withAnimation(.snappy(duration: 0.28)) { items = normalized }
        if let filter, !items.contains(where: { $0.groupKey == filter }) { self.filter = nil }
        if let replyingID, !items.contains(where: { $0.id == replyingID }) { self.replyingID = nil }
        if let alert, !items.contains(where: { $0.id == alert.id }) { dismissAlert() }
        scheduleSave()
    }

    func dismiss(_ item: NotchNotification) {
        if let banner = item.liveBannerID {
            Task { await CommunicationsManager.shared.dismissNotification(id: banner) }
        }
        replaceItems(items.filter { $0.id != item.id })
    }

    /// Clears what is on screen (one app when filtered) and offers Undo.
    func clearVisible() {
        let removed = visibleItems
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map(\.id))
        replaceItems(items.filter { !removedIDs.contains($0.id) })
        if filter == nil { CommunicationsManager.shared.clearHistory() }
        offerUndo(removed)
    }

    func clearGroup(_ key: String) {
        let removed = items.filter { $0.groupKey == key }
        guard !removed.isEmpty else { return }
        replaceItems(items.filter { $0.groupKey != key })
        offerUndo(removed)
    }

    func undoClear() {
        guard let snapshot = undoSnapshot else { return }
        undoTask?.cancel()
        withAnimation(.snappy) { undoSnapshot = nil }
        replaceItems(snapshot + items)
    }

    private func offerUndo(_ removed: [NotchNotification]) {
        withAnimation(.snappy) { undoSnapshot = removed }
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.undoSnapshot = nil }
        }
    }

    func mute(_ item: NotchNotification) {
        guard let bundle = item.bundleIdentifier else { return }
        var muted = Defaults[.notificationMutedApps]
        if !muted.contains(bundle) { muted.append(bundle) }
        Defaults[.notificationMutedApps] = muted
    }

    func unmute(_ bundle: String) {
        Defaults[.notificationMutedApps] = Defaults[.notificationMutedApps].filter { $0 != bundle }
    }

    private func isMuted(_ bundle: String?) -> Bool {
        guard let bundle else { return false }
        return Defaults[.notificationMutedApps].contains(bundle)
    }

    // MARK: Actions

    func canReply(_ item: NotchNotification) -> Bool { item.reply.isAvailable }

    /// Sends a reply through whichever route the notification supports.
    @discardableResult
    func sendReply(_ text: String, to item: NotchNotification) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sendingIDs.contains(item.id) else { return false }
        sendingIDs.insert(item.id)
        defer { sendingIDs.remove(item.id) }
        lastError = nil

        var sent = false
        switch item.reply {
        case .none:
            lastError = "\(item.appName) does not accept replies from the notch. Open it instead."
        case .whatsapp(let chatJID):
            sent = await WhatsAppManager.shared.send(trimmed, to: chatJID)
            if !sent { lastError = WhatsAppManager.shared.lastSendError ?? "WhatsApp could not send the reply." }
        case .messages(let chatID):
            do {
                try await AppleScriptHelper.executeVoid(NotchNotificationPolicy.messagesReplyScript(text: trimmed, chatID: chatID))
                sent = true
            } catch {
                lastError = "Messages did not send the reply. Allow NotchFlow to control Messages in System Settings › Privacy & Security › Automation, or open the conversation."
            }
        case .banner(let bannerID):
            let manager = CommunicationsManager.shared
            if await manager.beginReply(id: bannerID) {
                sent = await manager.sendReply(trimmed, id: bannerID)
            }
            if !sent {
                lastError = manager.lastError ?? "The banner closed before the reply could be sent. Open the app to answer."
            }
        }

        if sent {
            // A promise you made in the reply (WhatsApp replies are seen by its gateway hook).
            switch item.reply {
            case .messages(let chat):
                PromiseKeeper.shared.observe(text: trimmed, fromMe: true, person: item.headline,
                                             route: .messages(chatID: chat), sourceName: item.appName, at: Date())
            case .banner:
                PromiseKeeper.shared.observe(text: trimmed, fromMe: true, person: item.headline,
                                             route: .none, sourceName: item.appName, at: Date())
            case .whatsapp, .none:
                break
            }
            withAnimation(.snappy) {
                repliedIDs.insert(item.id)
                if replyingID == item.id { replyingID = nil }
            }
        }
        return sent
    }

    func open(_ item: NotchNotification) {
        if let banner = item.liveBannerID {
            Task { await CommunicationsManager.shared.openNotification(id: banner) }
            return
        }
        if case .whatsapp(let chatJID) = item.reply, WhatsAppManager.shared.state.isLinked {
            DynamicIslandViewCoordinator.shared.currentView = .whatsapp
            WhatsAppManager.shared.openChat(chatJID)
            return
        }
        guard let bundle = item.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            lastError = "\(item.appName) could not be found on this Mac."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Closed-notch alert

    private func showAlert(_ item: NotchNotification) {
        guard enabled, Defaults[.notificationAlertInNotch] else { return }
        if Defaults[.communicationRespectFocus] && DoNotDisturbManager.shared.isDoNotDisturbActive { return }
        if LockScreenManager.shared.isLocked { return }
        // A Pomodoro focus block keeps it in the inbox without announcing it.
        if FocusQuiet.shared.shouldHold(.notification) { return }
        withAnimation(.snappy) { alert = item }
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.alert = nil }
        }
    }

    func highlight(_ id: String) {
        highlightedID = id
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.highlightedID = nil }
        }
    }

    func dismissAlert() {
        alertTask?.cancel()
        alertTask = nil
        if alert != nil { withAnimation(.snappy) { alert = nil } }
    }

    // MARK: App names

    func appName(for bundle: String) -> String {
        if let cached = appNames[bundle] { return cached }
        var name = bundle.split(separator: ".").last.map { String($0).capitalized } ?? bundle
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let display = FileManager.default.displayName(atPath: url.path)
            name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        }
        appNames[bundle] = name
        return name
    }

    // MARK: Persistence

    nonisolated private static var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/Notifications", isDirectory: true)
            .appendingPathComponent("inbox.json")
    }

    private static func loadHistory() -> [NotchNotification] {
        guard let data = try? Data(contentsOf: historyURL),
              let items = try? JSONDecoder().decode([NotchNotification].self, from: data) else { return [] }
        // Live banner actions do not survive a relaunch.
        return items.map { item in
            var copy = item
            copy.liveBannerID = nil
            if case .banner = copy.reply { copy.reply = .none }
            return copy
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        let url = Self.historyURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: [.atomic])
            }
        }
    }

    /// Deletes the stored inbox, e.g. when the feature is turned off for good.
    func eraseHistory() {
        replaceItems([])
        try? FileManager.default.removeItem(at: Self.historyURL)
    }
}
