/*
 * NotchFlow
 * Copyright (C) 2026 dhruvv620
 * Portions Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Combine
import Defaults
import Foundation

/// Owns the WhatsApp integration: the GOWA gateway process, linking by QR
/// code, the chat list with unread counts, and the messages shown in the notch.
///
/// The gateway keeps its own SQLite copy of chats and messages; NotchFlow reads it
/// over the REST API and learns about new messages from the gateway's webhook,
/// so a message reaches the notch the moment it arrives. A slow poll runs as
/// well, in case a webhook delivery is lost.
///
/// Unread counts are NotchFlow's own. The gateway does not report WhatsApp's
/// unread state, so a chat counts as read up to the last time it was read in
/// NotchFlow, read on another device (a `read-self` receipt), or answered. Nothing
/// sent before the account was linked to NotchFlow counts as unread.
@MainActor
final class WhatsAppManager: ObservableObject {
    static let shared = WhatsAppManager()

    // MARK: Published state

    @Published private(set) var state: WhatsAppConnectionState = .disabled
    @Published private(set) var installedVersion: String = Defaults[.whatsAppGatewayVersion]
    @Published private(set) var latestVersion: String?
    @Published private(set) var isCheckingForUpdate = false

    @Published private(set) var qrImage: NSImage?
    @Published private(set) var qrExpiresAt: Date?
    @Published private(set) var isLinking = false

    @Published private(set) var chats: [WhatsAppChat] = []
    @Published private(set) var messages: [String: [WhatsAppMessage]] = [:]
    @Published private(set) var loadingChatIDs: Set<String> = []
    @Published private(set) var isRefreshingChats = false
    @Published var selectedChatID: String?

    @Published private(set) var banner: WhatsAppIncomingBanner?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSendError: String?
    /// True once a webhook delivery has arrived, i.e. new messages show up at once.
    @Published private(set) var receivesLiveUpdates = false
    /// Each account's own link state (waiting for a scan, connected,
    /// reconnecting) and number. `state` sums them up: connected when any is.
    @Published private(set) var linkStates: [WhatsAppAccountSlot: WhatsAppConnectionState] = [:]
    @Published private(set) var accountJIDs: [WhatsAppAccountSlot: String] = [:]
    /// The account the QR code on screen is for.
    @Published private(set) var linkingSlot: WhatsAppAccountSlot?

    /// Set by the notch tab while it is on screen.
    var isTabVisible = false

    var visibleChats: [WhatsAppChat] {
        let ignored = Set(Defaults[.whatsAppIgnoredChats])
        return chats.filter { !$0.archived && !ignored.contains($0.id) }
    }

    var totalUnread: Int {
        visibleChats.reduce(0) { $0 + $1.unreadCount }
    }

    var hasUpdate: Bool {
        guard let latestVersion, !installedVersion.isEmpty else { return false }
        return latestVersion.compare(installedVersion, options: .numeric) == .orderedDescending
    }

    var accountPhone: String { phone(for: .primary) }

    func phone(for slot: WhatsAppAccountSlot) -> String { WhatsAppJID.displayNumber(accountJIDs[slot] ?? "") }

    /// The accounts in use: the first, and the second once you add it.
    var activeSlots: [WhatsAppAccountSlot] {
        Defaults[.whatsAppSecondAccountEnabled] ? [.primary, .second] : [.primary]
    }

    /// One account's own state: its link state while the gateway runs, else the gateway's.
    func linkState(for slot: WhatsAppAccountSlot) -> WhatsAppConnectionState {
        if gateway != nil, let own = linkStates[slot] { return own }
        // Not heard from yet: the gateway's own state (starting, failed…), or waiting for a scan.
        return state.isLinked || state == .waitingForLink ? .waitingForLink : state
    }

    /// Both accounts linked: chats are labelled with the account's name.
    var hasTwoLinkedAccounts: Bool {
        activeSlots.count > 1 && activeSlots.allSatisfy { linkStates[$0]?.isLinked == true }
    }

    func accountName(_ slot: WhatsAppAccountSlot) -> String {
        let name = (Defaults[.whatsAppAccountNames][slot.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return slot == .primary ? String(localized: "Account 1") : String(localized: "Account 2")
    }

    func setAccountName(_ name: String, for slot: WhatsAppAccountSlot) {
        var names = Defaults[.whatsAppAccountNames]
        names[slot.rawValue] = name
        Defaults[.whatsAppAccountNames] = names
        objectWillChange.send()
    }

    /// The account label to show beside a chat, when two accounts are linked.
    func accountLabel(for chatID: String) -> String? {
        hasTwoLinkedAccounts ? accountName(WhatsAppAccountSlot.of(chatID)) : nil
    }

    /// Whether a message can go out to this chat right now.
    func canSend(to chatID: String) -> Bool {
        linkStates[WhatsAppAccountSlot.of(chatID)]?.isConnected == true
    }

    // MARK: Private state

    private let username = "notchflow"
    private static let deviceName = "NotchFlow"
    /// Messages kept in memory per chat.
    private static let messageCacheLimit = 200
    /// How many of the most recent chats get their latest messages fetched,
    /// for previews and unread counts.
    private static let summarizedChatCount = 25

    /// The running gateway's address and this launch's password.
    private var gateway: (url: URL, password: String)?
    private let process = WhatsAppGatewayProcess()
    private var webhook: WhatsAppWebhookServer?

    private var monitorTask: Task<Void, Never>?
    private var linkTask: Task<Void, Never>?
    /// The current QR session, so a cancelled one doesn't tidy up the next.
    private var linkToken = UUID()
    private var bannerTask: Task<Void, Never>?
    private var scheduledChatRefresh: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var lastFullRefresh: Date = .distantPast
    private var lastReconnectAttempt: [WhatsAppAccountSlot: Date] = [:]
    private var unexpectedExitCount = 0
    private var started = false

    private init() {}

    /// The gateway client for one account (its slot rides along on every request).
    private func client(for slot: WhatsAppAccountSlot) -> WhatsAppGatewayClient? {
        guard let gateway else { return nil }
        return WhatsAppGatewayClient(baseURL: gateway.url, username: username, password: gateway.password, deviceID: slot.rawValue)
    }

    /// The first account's client, for calls about the gateway itself.
    private var client: WhatsAppGatewayClient? { client(for: .primary) }

    // MARK: Lifecycle

    /// Called once at launch. Follows the feature toggle from then on.
    func start() {
        guard !started else { return }
        started = true
        Defaults.publisher(.enableWhatsAppFeature)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    Task { await self.bootstrap() }
                } else {
                    self.shutdownGateway()
                    self.clearConversations()
                    self.state = .disabled
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate() {
        shutdownGateway()
    }

    func bootstrap() async {
        guard Defaults[.enableWhatsAppFeature] else {
            state = .disabled
            return
        }
        guard WhatsAppGatewayInstaller.isInstalled else {
            state = .notInstalled
            return
        }
        await launchGateway()
    }

    /// Restarts the gateway, e.g. after it stopped or failed to start.
    func restartGateway() {
        Task { await bootstrap() }
    }

    private func launchGateway() async {
        shutdownGateway()
        state = .starting
        lastError = nil

        let password = Self.randomToken(length: 32)
        let secret = Self.randomToken(length: 48)

        let server = WhatsAppWebhookServer(secret: secret) { @Sendable [weak self] data in
            Task { @MainActor in self?.handleWebhook(data) }
        }
        let webhookPort: UInt16
        do {
            webhookPort = try await server.start()
        } catch {
            fail(String(localized: "NotchFlow could not open a local port for new messages: \(error.localizedDescription)"))
            return
        }
        webhook = server

        guard let apiPort = WhatsAppGatewayProcess.freePort() else {
            fail(String(localized: "No free local port was found for the gateway."))
            return
        }

        process.onExit = { @Sendable [weak self] status in
            Task { @MainActor in self?.gatewayExited(status: status) }
        }
        do {
            try process.start(.init(
                port: apiPort,
                username: username,
                password: password,
                webhookURL: "http://127.0.0.1:\(webhookPort)\(WhatsAppWebhookServer.path)",
                webhookSecret: secret,
                deviceName: Self.deviceName
            ))
        } catch {
            fail(String(localized: "The gateway could not be started: \(error.localizedDescription)"))
            return
        }

        gateway = (URL(string: "http://127.0.0.1:\(apiPort)")!, password)
        guard let client else { return }

        // The gateway opens its database and connects before it serves HTTP.
        var info: GOWAAppInfo?
        for _ in 0..<60 {
            guard process.isRunning else { break }
            if let answer = try? await client.appInfo() {
                info = answer
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard info != nil, gateway != nil else {
            if gateway != nil {
                shutdownGateway()
                fail(String(localized: "The gateway did not respond. Its log is in Application Support › NotchFlow › WhatsAppGateway."))
            }
            return
        }
        if let version = info?.version, !version.isEmpty {
            let clean = version.hasPrefix("v") ? String(version.dropFirst()) : version
            if clean != installedVersion {
                installedVersion = clean
                Defaults[.whatsAppGatewayVersion] = clean
            }
        }

        do {
            let devices = try await client.devices()
            for slot in activeSlots where !devices.contains(where: { $0.id == slot.rawValue }) {
                try await self.client(for: slot)?.createDevice()
            }
        } catch {
            shutdownGateway()
            fail(error.localizedDescription)
            return
        }

        await refreshStatus()
        startMonitor()
    }

    private func shutdownGateway() {
        linkTask?.cancel()
        linkTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        restartTask?.cancel()
        restartTask = nil
        scheduledChatRefresh?.cancel()
        scheduledChatRefresh = nil
        process.onExit = nil
        process.stop()
        webhook?.stop()
        webhook = nil
        gateway = nil
        linkStates = [:]
        receivesLiveUpdates = false
        isLinking = false
        linkingSlot = nil
        qrImage = nil
        qrExpiresAt = nil
    }

    private func gatewayExited(status: Int32) {
        gateway = nil
        linkStates = [:]
        webhook?.stop()
        webhook = nil
        monitorTask?.cancel()
        guard Defaults[.enableWhatsAppFeature] else { return }

        unexpectedExitCount += 1
        if unexpectedExitCount <= 3 {
            state = .starting
            restartTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(2 * Double(NSEC_PER_SEC)))
                guard let self, !Task.isCancelled else { return }
                await self.bootstrap()
            }
        } else {
            fail(String(localized: "The gateway stopped unexpectedly (status \(status))."))
        }
    }

    private func fail(_ message: String) {
        lastError = message
        state = .failed(message)
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * NSEC_PER_SEC)
                guard let self, !Task.isCancelled else { return }
                await self.refreshStatus()
                guard self.state.isConnected else { continue }
                // With live webhooks the poll is only a safety net.
                let interval: TimeInterval = self.receivesLiveUpdates ? 300 : 45
                if Date().timeIntervalSince(self.lastFullRefresh) > interval {
                    await self.refreshChats()
                }
            }
        }
    }

    // MARK: Status and linking

    func refreshStatus() async {
        for slot in activeSlots {
            await refreshStatus(slot)
        }
        recomputeState()
    }

    private func refreshStatus(_ slot: WhatsAppAccountSlot) async {
        guard let client = self.client(for: slot) else { return }
        do {
            let status = try await client.status()
            let jid = status.jid ?? ""
            let loggedIn = status.isLoggedIn ?? false
            let linked = loggedIn || !jid.isEmpty
            guard linked else {
                accountJIDs[slot] = nil
                if linkStates[slot] != .waitingForLink { linkStates[slot] = .waitingForLink }
                return
            }

            let wasLinked = linkStates[slot]?.isLinked ?? false
            if !jid.isEmpty { accountJIDs[slot] = jid }
            let phone = self.phone(for: slot)
            if loggedIn && (status.isConnected ?? false) {
                if linkStates[slot] != .connected(phone: phone) { linkStates[slot] = .connected(phone: phone) }
                unexpectedExitCount = 0
            } else {
                linkStates[slot] = .reconnecting(phone: phone)
                if Date().timeIntervalSince(lastReconnectAttempt[slot] ?? .distantPast) > 30 {
                    lastReconnectAttempt[slot] = Date()
                    try? await client.reconnect()
                }
            }
            if !wasLinked {
                didLink(slot)
            }
        } catch WhatsAppGatewayError.notRunning {
            // The exit handler restarts the gateway.
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The overall state from the accounts': connected when any account is,
    /// so everything that sends or lists chats works with either.
    private func recomputeState() {
        guard gateway != nil else { return }
        let linked = activeSlots.filter { linkStates[$0]?.isLinked == true }
        let next: WhatsAppConnectionState
        if let connected = linked.first(where: { linkStates[$0]?.isConnected == true }) {
            next = .connected(phone: phone(for: connected))
        } else if let first = linked.first {
            next = .reconnecting(phone: phone(for: first))
        } else if activeSlots.contains(where: { linkStates[$0] != nil }) {
            next = .waitingForLink
        } else {
            return
        }
        if state != next { state = next }
    }

    /// Shows a QR code to scan from WhatsApp › Settings › Linked devices on
    /// the phone of the account being linked. Codes expire, so a fresh one
    /// is requested until the scan succeeds or a few minutes pass.
    func beginLinking(_ slot: WhatsAppAccountSlot = .primary) {
        guard gateway != nil, linkStates[slot]?.isLinked != true else { return }
        linkTask?.cancel()
        isLinking = true
        linkingSlot = slot
        qrImage = nil
        lastError = nil
        let token = UUID()
        linkToken = token

        linkTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.linkToken == token {
                    self.isLinking = false
                    self.linkingSlot = nil
                    self.qrImage = nil
                    self.qrExpiresAt = nil
                }
            }
            @MainActor func linked() async -> Bool {
                await self.refreshStatus(slot)
                self.recomputeState()
                return self.linkStates[slot]?.isLinked == true
            }
            for _ in 0..<6 {
                guard !Task.isCancelled, let client = self.client(for: slot) else { return }
                if await linked() { return }
                do {
                    let login = try await client.login()
                    if let link = login.qrLink, let data = try? await client.qrImageData(link: link) {
                        self.qrImage = NSImage(data: data)
                    }
                    let duration = TimeInterval(max(15, min(login.qrDuration ?? 30, 60)))
                    self.qrExpiresAt = Date().addingTimeInterval(duration)
                    let deadline = Date().addingTimeInterval(duration)
                    while Date() < deadline {
                        try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                        if Task.isCancelled { return }
                        if await linked() { return }
                    }
                } catch let error as WhatsAppGatewayError where error.code == "ALREADY_LOGGED_IN" || error.code == "SESSION_SAVED_ERROR" {
                    try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                    _ = await linked()
                    return
                } catch {
                    if !Task.isCancelled { self.lastError = error.localizedDescription }
                    return
                }
            }
        }
    }

    func cancelLinking() {
        linkTask?.cancel()
        linkTask = nil
    }

    /// Adds a second account (say, personal next to business) and shows its QR code.
    func addSecondAccount() async {
        Defaults[.whatsAppSecondAccountEnabled] = true
        objectWillChange.send()
        guard let client = self.client(for: .second) else { return }
        do {
            let devices = try await client.devices()
            if !devices.contains(where: { $0.id == WhatsAppAccountSlot.second.rawValue }) {
                try await client.createDevice()
            }
        } catch {
            lastError = error.localizedDescription
            return
        }
        await refreshStatus(.second)
        recomputeState()
        beginLinking(.second)
    }

    private static func linkedAtKey(_ slot: WhatsAppAccountSlot) -> Defaults.Key<Double> {
        slot == .primary ? .whatsAppLinkedAt : .whatsAppSecondLinkedAt
    }

    private func didLink(_ slot: WhatsAppAccountSlot) {
        if linkingSlot == slot {
            linkTask?.cancel()
            linkTask = nil
        }
        if Defaults[Self.linkedAtKey(slot)] == 0 {
            Defaults[Self.linkedAtKey(slot)] = Date().timeIntervalSince1970
        }
        Task { await refreshChats() }
    }

    /// Logs an account out of the gateway, which also removes "NotchFlow"
    /// from that phone's linked devices. The second account is removed
    /// altogether.
    func unlink(_ slot: WhatsAppAccountSlot = .primary) async {
        cancelLinking()
        let client = self.client(for: slot)
        if let client {
            try? await client.logout()
        }
        forget(slot)
        if slot == .second {
            try? await client?.removeDevice()
            Defaults[.whatsAppSecondAccountEnabled] = false
            Defaults[.whatsAppAccountNames][slot.rawValue] = nil
            linkStates[slot] = nil
        }
        await refreshStatus()
    }

    /// Drops what NotchFlow knows of one account's chats.
    private func forget(_ slot: WhatsAppAccountSlot) {
        clearConversations(of: slot)
        Defaults[.whatsAppLastRead] = Defaults[.whatsAppLastRead].filter { WhatsAppAccountSlot.of($0.key) != slot }
        Defaults[Self.linkedAtKey(slot)] = 0
        accountJIDs[slot] = nil
    }

    private func clearConversations() {
        chats = []
        messages = [:]
        selectedChatID = nil
        banner = nil
        loadingChatIDs = []
    }

    private func clearConversations(of slot: WhatsAppAccountSlot) {
        func mine(_ id: String) -> Bool { WhatsAppAccountSlot.of(id) == slot }
        chats.removeAll { mine($0.id) }
        messages = messages.filter { !mine($0.key) }
        if let selectedChatID, mine(selectedChatID) { self.selectedChatID = nil }
        if let banner, mine(banner.chatJID) { self.banner = nil }
        loadingChatIDs = loadingChatIDs.filter { !mine($0) }
    }

    // MARK: Install and update

    func checkForUpdate() async {
        guard !isCheckingForUpdate else { return }
        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }
        do {
            latestVersion = try await WhatsAppGatewayInstaller.latestRelease().version
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Downloads the latest gateway and (re)starts it. The linked session is
    /// kept: it lives in the gateway's data directory, not in the binary.
    func installOrUpdateGateway() async {
        if case .installing = state { return }
        lastError = nil
        let previousState = state
        state = .installing(progress: nil)
        do {
            let release = try await WhatsAppGatewayInstaller.latestRelease()
            shutdownGateway()
            state = .installing(progress: 0)
            try await WhatsAppGatewayInstaller.install(release) { fraction in
                Task { @MainActor in
                    if case .installing = WhatsAppManager.shared.state {
                        WhatsAppManager.shared.state = .installing(progress: fraction)
                    }
                }
            }
            installedVersion = release.version
            latestVersion = release.version
            Defaults[.whatsAppGatewayVersion] = release.version
            unexpectedExitCount = 0
            await bootstrap()
        } catch {
            lastError = error.localizedDescription
            if WhatsAppGatewayInstaller.isInstalled, Defaults[.enableWhatsAppFeature] {
                if case .failed = previousState {
                    state = previousState
                } else {
                    await bootstrap()
                }
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Unlinks, stops the gateway and deletes it along with its data.
    func removeGateway() async {
        if Defaults[.whatsAppSecondAccountEnabled] { await unlink(.second) }
        await unlink()
        shutdownGateway()
        WhatsAppGatewayInstaller.uninstall()
        WhatsAppGatewayInstaller.removeData()
        installedVersion = ""
        Defaults[.whatsAppGatewayVersion] = ""
        state = Defaults[.enableWhatsAppFeature] ? .notInstalled : .disabled
    }

    // MARK: Chats

    func refreshChats() async {
        let slots = activeSlots.filter { linkStates[$0]?.isLinked == true }
        guard gateway != nil, !slots.isEmpty, !isRefreshingChats else { return }
        isRefreshingChats = true
        defer { isRefreshingChats = false }

        let previous = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [WhatsAppChat] = []
        var seen = Set<String>()
        for slot in slots {
            guard let client = self.client(for: slot) else { continue }
            let remote: [GOWAChat]
            do {
                remote = try await client.chats(limit: 40)
            } catch {
                if let gatewayError = error as? WhatsAppGatewayError, case .notRunning = gatewayError { return }  // Restarted by the exit handler.
                lastError = error.localizedDescription
                // Keep what this account had rather than emptying its chats.
                updated += chats.filter { WhatsAppAccountSlot.of($0.id) == slot && seen.insert($0.id).inserted }
                continue
            }
            for item in remote where !WhatsAppJID.isHidden(item.jid) {
                let id = slot.scope(item.jid)
                guard seen.insert(id).inserted else { continue }
                let old = previous[id]
                let remoteName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                updated.append(WhatsAppChat(
                    id: id,
                    name: remoteName.isEmpty ? (old?.name ?? "") : remoteName,
                    lastMessageTime: WhatsAppDateParser.parse(item.lastMessageTime) ?? old?.lastMessageTime,
                    archived: item.archived ?? false,
                    preview: old?.preview,
                    previewIsFromMe: old?.previewIsFromMe ?? false,
                    previewSender: old?.previewSender,
                    unreadCount: old?.unreadCount ?? 0
                ))
            }
        }

        for chat in Self.sorted(updated).prefix(Self.summarizedChatCount * slots.count) {
            let old = previous[chat.id]
            if let old, old.lastMessageTime == chat.lastMessageTime, messages[chat.id] != nil { continue }
            guard let client = self.client(for: WhatsAppAccountSlot.of(chat.id)),
                  let recent = try? await client.messages(chatJID: WhatsAppJID.bare(chat.id), limit: 20) else { continue }
            merge(Self.messages(recent, in: chat.id), into: chat.id)
        }

        // Chats that only exist locally (a webhook raced this refresh) are kept.
        let remoteIDs = Set(updated.map(\.id))
        for chat in chats where !remoteIDs.contains(chat.id) && chat.lastMessageTime.map({ Date().timeIntervalSince($0) < 600 }) == true {
            updated.append(chat)
        }

        for index in updated.indices {
            summarize(&updated[index])
        }
        chats = Self.sorted(updated)
        lastFullRefresh = Date()
    }

    /// The gateway's messages of a chat, filed under NotchFlow's id for it.
    private static func messages(_ items: [GOWAMessage], in chatID: String) -> [WhatsAppMessage] {
        items.map { item in
            var message = item.toMessage(fallbackChatJID: WhatsAppJID.bare(chatID))
            message.chatJID = chatID
            return message
        }
    }

    private func scheduleChatRefresh() {
        guard scheduledChatRefresh == nil else { return }
        scheduledChatRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
            guard let self, !Task.isCancelled else { return }
            self.scheduledChatRefresh = nil
            await self.refreshChats()
        }
    }

    func chat(id: String) -> WhatsAppChat? {
        chats.first { $0.id == id }
    }

    func isIgnored(_ chatID: String) -> Bool {
        Defaults[.whatsAppIgnoredChats].contains(chatID)
    }

    func setIgnored(_ ignored: Bool, chatID: String) {
        var list = Defaults[.whatsAppIgnoredChats]
        var names = Defaults[.whatsAppIgnoredChatNames]
        if ignored {
            if !list.contains(chatID) { list.append(chatID) }
            names[chatID] = chat(id: chatID)?.displayName ?? WhatsAppJID.displayNumber(chatID)
            if selectedChatID == chatID { selectedChatID = nil }
        } else {
            list.removeAll { $0 == chatID }
            names[chatID] = nil
        }
        Defaults[.whatsAppIgnoredChats] = list
        Defaults[.whatsAppIgnoredChatNames] = names
        objectWillChange.send()
    }

    // MARK: Conversations

    func openChat(_ chatID: String) {
        selectedChatID = chatID
        lastSendError = nil
        Task {
            await loadMessages(chatID)
            if Defaults[.whatsAppMarkReadOnOpen] {
                await markChatRead(chatID)
            }
        }
    }

    func closeChat() {
        selectedChatID = nil
        lastSendError = nil
    }

    func loadMessages(_ chatID: String) async {
        guard let client = self.client(for: WhatsAppAccountSlot.of(chatID)), !loadingChatIDs.contains(chatID) else { return }
        loadingChatIDs.insert(chatID)
        defer { loadingChatIDs.remove(chatID) }
        do {
            let recent = try await client.messages(chatJID: WhatsAppJID.bare(chatID), limit: 50)
            merge(Self.messages(recent, in: chatID), into: chatID)
            resummarize(chatID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Marks the chat read in NotchFlow and sends read receipts for its unread
    /// messages, which clears them on the phone as well.
    func markChatRead(_ chatID: String) async {
        let unreadIDs = unreadIncomingMessages(in: chatID).map(\.id)
        markReadLocally(chatID, at: Date())
        guard let client = self.client(for: WhatsAppAccountSlot.of(chatID)), !unreadIDs.isEmpty else { return }
        for id in unreadIDs.suffix(20) {
            try? await client.markRead(messageID: id, chatJID: WhatsAppJID.bare(chatID))
        }
    }

    @discardableResult
    func send(_ text: String, to chatID: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let slot = WhatsAppAccountSlot.of(chatID)
        guard let client = self.client(for: slot), canSend(to: chatID) else {
            lastSendError = hasTwoLinkedAccounts || slot == .second
                ? String(localized: "\(accountName(slot)) on WhatsApp is not connected right now.")
                : String(localized: "WhatsApp is not connected right now.")
            return false
        }
        lastSendError = nil

        let pendingID = WhatsAppMessage.pendingPrefix + UUID().uuidString
        let pending = WhatsAppMessage(
            id: pendingID,
            chatJID: chatID,
            senderJID: accountJIDs[slot] ?? "",
            senderName: String(localized: "You"),
            text: trimmed,
            timestamp: Date(),
            isFromMe: true
        )
        let unreadIDs = unreadIncomingMessages(in: chatID).map(\.id)
        merge([pending], into: chatID)
        resummarize(chatID)

        do {
            let sentID = try await client.sendText(to: WhatsAppJID.bare(chatID), text: trimmed)
            replacePending(pendingID, in: chatID, with: sentID)
            PromiseKeeper.shared.observe(text: trimmed, fromMe: true, person: chat(id: chatID)?.displayName ?? "",
                                         route: .whatsapp(chatJID: chatID), sourceName: "WhatsApp", at: Date(),
                                         replyingTo: lastText(in: chatID, before: pending.timestamp, fromMe: false))
            markReadLocally(chatID, at: Date())
            // Replying means the messages before it were read.
            for id in unreadIDs.suffix(20) {
                try? await client.markRead(messageID: id, chatJID: WhatsAppJID.bare(chatID))
            }
            return true
        } catch {
            removeMessage(pendingID, in: chatID)
            resummarize(chatID)
            lastSendError = error.localizedDescription
            return false
        }
    }

    /// Sends files from the Shelf (or anywhere) to a chat.
    @discardableResult
    func sendFiles(_ urls: [URL], to chatID: String) async -> Bool {
        guard let client = self.client(for: WhatsAppAccountSlot.of(chatID)), canSend(to: chatID) else {
            lastSendError = String(localized: "WhatsApp is not connected right now.")
            return false
        }
        lastSendError = nil
        for url in urls {
            do {
                _ = try await client.sendFile(to: WhatsAppJID.bare(chatID), fileURL: url)
            } catch {
                lastSendError = error.localizedDescription
                return false
            }
        }
        markReadLocally(chatID, at: Date())
        Task { await loadMessages(chatID) }
        return true
    }

    // MARK: Banner

    func dismissBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        banner = nil
    }

    private func showBanner(for message: WhatsAppMessage, mentionsMe: Bool) {
        let chatID = message.chatJID
        guard Defaults[.whatsAppShowIncomingMessages] else { return }
        // Offline messages are delivered in a burst when the gateway
        // reconnects; only announce what just arrived.
        guard Date().timeIntervalSince(message.timestamp) < 120 else { return }
        guard !isIgnored(chatID) else { return }
        if WhatsAppJID.isGroup(chatID) && Defaults[.whatsAppMuteGroups] && !mentionsMe { return }
        if Defaults[.whatsAppQuietDuringFocus] && DoNotDisturbManager.shared.isDoNotDisturbActive { return }
        if LockScreenManager.shared.isLocked { return }
        if isTabVisible && selectedChatID == chatID { return }
        // During a Pomodoro focus block the message waits in the WhatsApp tab.
        if FocusQuiet.shared.shouldHold(.message) { return }

        let chatName = chat(id: chatID)?.displayName ?? message.senderName
        let text = Defaults[.whatsAppShowMessagePreviews]
            ? message.previewText
            : String(localized: "New message")
        banner = WhatsAppIncomingBanner(
            id: message.id,
            chatJID: chatID,
            chatName: chatName,
            senderName: message.senderName,
            text: text,
            isGroup: WhatsAppJID.isGroup(chatID)
        )
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6 * NSEC_PER_SEC)
            guard let self, !Task.isCancelled else { return }
            self.banner = nil
        }
    }

    // MARK: Webhook

    private func handleWebhook(_ data: Data) {
        guard let event = WhatsAppWebhookEvent(data: data) else { return }
        receivesLiveUpdates = true
        let slot = WhatsAppAccountSlot.forEvent(sessionID: event.sessionID, deviceJID: event.deviceJID, accounts: accountJIDs)
        guard activeSlots.contains(slot) else { return }
        /// A chat named in the event, as NotchFlow files it for this account.
        func scopedChat(_ key: String) -> String? { event.string(key).map(slot.scope) }

        switch event.event {
        case "message":
            handleMessageEvent(event, slot: slot)
        case "message.edited":
            guard let chatID = scopedChat("chat_id"), let original = event.string("original_message_id") else { return }
            updateMessage(original, in: chatID) { message in
                message.text = event.string("body") ?? message.text
                message.isEdited = true
            }
        case "message.revoked":
            guard let original = event.string("revoked_message_id") else { return }
            let chatID = scopedChat("revoked_chat") ?? scopedChat("chat_id") ?? ""
            updateMessage(original, in: chatID) { message in
                message.isRevoked = true
                message.text = ""
            }
        case "message.deleted":
            guard let chatID = scopedChat("chat_id"), let original = event.string("deleted_message_id") else { return }
            removeMessage(original, in: chatID)
            resummarize(chatID)
        case "message.ack":
            handleReceipt(event, slot: slot)
        case "device.logged_out":
            forget(slot)
            linkStates[slot] = .waitingForLink
            recomputeState()
            Task { await refreshStatus() }
        default:
            break
        }
    }

    private func handleMessageEvent(_ event: WhatsAppWebhookEvent, slot: WhatsAppAccountSlot) {
        guard var message = event.message(), !WhatsAppJID.isHidden(message.chatJID) else { return }
        message.chatJID = slot.scope(message.chatJID)
        // Protocol messages and types NotchFlow cannot describe carry no text and no media.
        guard !message.text.isEmpty || message.mediaType != nil else { return }
        let chatID = message.chatJID

        merge([message], into: chatID)
        if message.isFromMe {
            // Sent from the phone (or another device): that chat was seen.
            markReadLocally(chatID, at: message.timestamp)
        }

        if let index = chats.firstIndex(where: { $0.id == chatID }) {
            var chat = chats[index]
            if !WhatsAppJID.isGroup(chatID), !message.isFromMe, chat.name.isEmpty {
                chat.name = message.senderName
            }
            chat.archived = false
            summarize(&chat)
            chats[index] = chat
            chats = Self.sorted(chats)
        } else {
            var chat = WhatsAppChat(
                id: chatID,
                name: (!WhatsAppJID.isGroup(chatID) && !message.isFromMe) ? message.senderName : "",
                lastMessageTime: message.timestamp,
                archived: false,
                preview: nil,
                previewIsFromMe: false,
                previewSender: nil,
                unreadCount: 0
            )
            summarize(&chat)
            chats = Self.sorted(chats + [chat])
            // A group's name is not in the message; fetch it.
            if chat.name.isEmpty { scheduleChatRefresh() }
        }

        // Promises you make or are made, in this chat (only recent messages count).
        let isGroup = WhatsAppJID.isGroup(chatID)
        let chatName = chat(id: chatID)?.displayName ?? message.senderName
        PromiseKeeper.shared.observe(text: message.text, fromMe: message.isFromMe,
                                     person: (isGroup && !message.isFromMe) ? message.senderName : chatName,
                                     route: .whatsapp(chatJID: chatID), sourceName: "WhatsApp", at: message.timestamp,
                                     replyingTo: lastText(in: chatID, before: message.timestamp, fromMe: !message.isFromMe,
                                                          excluding: message.id))

        guard !message.isFromMe else {
            // You answered this chat (from the notch or your phone): its notifications are read.
            if Date().timeIntervalSince(message.timestamp) < 600 {
                NotificationHub.shared.clearConversation(answeredIn: .whatsapp(chatJID: chatID))
            }
            return
        }
        if !isIgnored(chatID), Date().timeIntervalSince(message.timestamp) < 600 {
            NotificationHub.shared.ingestWhatsApp(
                message,
                chatName: chat(id: chatID)?.displayName ?? message.senderName,
                isGroup: WhatsAppJID.isGroup(chatID),
                account: accountLabel(for: chatID)
            )
        }
        if isTabVisible && selectedChatID == chatID && Defaults[.whatsAppMarkReadOnOpen] {
            Task { await markChatRead(chatID) }
            return
        }
        showBanner(for: message, mentionsMe: mentionsMe(event, slot: slot))
    }

    private func mentionsMe(_ event: WhatsAppWebhookEvent, slot: WhatsAppAccountSlot) -> Bool {
        let me = WhatsAppJID.user(accountJIDs[slot] ?? "")
        guard !me.isEmpty else { return false }
        if event.strings("mentions").contains(where: { WhatsAppJID.user($0) == me }) { return true }
        if let quoted = event.string("replied_to_sender"), WhatsAppJID.user(quoted) == me { return true }
        if let body = event.string("body"), body.contains("@\(me)") { return true }
        return false
    }

    private func handleReceipt(_ event: WhatsAppWebhookEvent, slot: WhatsAppAccountSlot) {
        let type = event.string("receipt_type") ?? ""
        guard type == "read" || type == "read-self",
              let chatID = event.string("chat_id"),
              let from = event.string("from"),
              WhatsAppJID.sameUser(from, accountJIDs[slot] ?? "") else { return }
        // The account read this chat on another device.
        markReadLocally(slot.scope(chatID), at: Date())
    }

    // MARK: Message cache

    private func merge(_ incoming: [WhatsAppMessage], into chatID: String) {
        guard !incoming.isEmpty else { return }
        var byID: [String: WhatsAppMessage] = [:]
        var order: [String] = []
        for message in (messages[chatID] ?? []) + incoming {
            if byID[message.id] == nil { order.append(message.id) }
            if let existing = byID[message.id] {
                // Keep local knowledge the gateway's copy may not reflect yet.
                var merged = message
                merged.isRevoked = existing.isRevoked || message.isRevoked
                merged.isEdited = existing.isEdited || message.isEdited
                byID[message.id] = merged
            } else {
                byID[message.id] = message
            }
        }
        var list = order.compactMap { byID[$0] }
        list.sort { $0.timestamp < $1.timestamp }
        if list.count > Self.messageCacheLimit {
            list.removeFirst(list.count - Self.messageCacheLimit)
        }
        messages[chatID] = list
    }

    private func updateMessage(_ id: String, in chatID: String, change: (inout WhatsAppMessage) -> Void) {
        guard var list = messages[chatID], let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
        messages[chatID] = list
        resummarize(chatID)
    }

    private func removeMessage(_ id: String, in chatID: String) {
        guard var list = messages[chatID] else { return }
        list.removeAll { $0.id == id }
        messages[chatID] = list
    }

    private func replacePending(_ pendingID: String, in chatID: String, with sentID: String?) {
        guard var list = messages[chatID], let index = list.firstIndex(where: { $0.id == pendingID }) else { return }
        guard let sentID, !sentID.isEmpty else {
            // Sent, but the gateway did not say under which id. Keep the bubble
            // as sent; the next refresh replaces it with the stored copy.
            list[index].isPendingConfirmed = true
            messages[chatID] = list
            return
        }
        if list.contains(where: { $0.id == sentID }) {
            list.remove(at: index)
        } else {
            let old = list[index]
            list[index] = WhatsAppMessage(
                id: sentID,
                chatJID: old.chatJID,
                senderJID: old.senderJID,
                senderName: old.senderName,
                text: old.text,
                timestamp: old.timestamp,
                isFromMe: true
            )
        }
        messages[chatID] = list
        resummarize(chatID)
    }

    // MARK: Read state

    private func readCutoff(for chatID: String) -> Date {
        let linked = Defaults[Self.linkedAtKey(WhatsAppAccountSlot.of(chatID))]
        let read = Defaults[.whatsAppLastRead][chatID] ?? 0
        return Date(timeIntervalSince1970: max(linked, read))
    }

    private func unreadIncomingMessages(in chatID: String) -> [WhatsAppMessage] {
        guard let list = messages[chatID] else { return [] }
        let lastOutgoing = list.last(where: { $0.isFromMe && !$0.isPending })?.timestamp ?? .distantPast
        let cutoff = max(readCutoff(for: chatID), lastOutgoing)
        return list.filter { !$0.isFromMe && !$0.isRevoked && $0.timestamp > cutoff }
    }

    private func markReadLocally(_ chatID: String, at date: Date) {
        var lastRead = Defaults[.whatsAppLastRead]
        let value = max(lastRead[chatID] ?? 0, date.timeIntervalSince1970)
        guard lastRead[chatID] != value else {
            resummarize(chatID)
            return
        }
        lastRead[chatID] = value
        Defaults[.whatsAppLastRead] = lastRead
        resummarize(chatID)
    }

    /// The latest message from one side of a chat before a moment, from the
    /// last day: what a reply like "ok bhai" answers.
    private func lastText(in chatID: String, before date: Date, fromMe: Bool, excluding id: String? = nil) -> String? {
        messages[chatID]?
            .filter { $0.isFromMe == fromMe && $0.id != id && !$0.isRevoked && $0.timestamp <= date
                && date.timeIntervalSince($0.timestamp) < 86_400 && !$0.text.isEmpty }
            .max { $0.timestamp < $1.timestamp }?.text
    }

    private func resummarize(_ chatID: String) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        var chat = chats[index]
        summarize(&chat)
        if chat != chats[index] {
            chats[index] = chat
            chats = Self.sorted(chats)
        }
    }

    private func summarize(_ chat: inout WhatsAppChat) {
        guard let list = messages[chat.id], let last = list.last else { return }
        chat.preview = last.previewText
        chat.previewIsFromMe = last.isFromMe
        chat.previewSender = (chat.isGroup && !last.isFromMe) ? Self.firstName(last.senderName) : nil
        if chat.lastMessageTime.map({ last.timestamp > $0 }) ?? true {
            chat.lastMessageTime = last.timestamp
        }
        chat.unreadCount = unreadIncomingMessages(in: chat.id).count
    }

    // MARK: Helpers

    private static func sorted(_ chats: [WhatsAppChat]) -> [WhatsAppChat] {
        chats.sorted { ($0.lastMessageTime ?? .distantPast) > ($1.lastMessageTime ?? .distantPast) }
    }

    private static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private static func randomToken(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))] })
    }
}
