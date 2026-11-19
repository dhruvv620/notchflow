// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Notice promises in the messages you send, and nudge before they're due.
    static let enablePromiseKeeper = Key<Bool>("enablePromiseKeeper", default: true)
    /// Also track what other people promise you.
    static let promiseTrackTheirs = Key<Bool>("promiseTrackTheirs", default: true)
    /// How long before a promise is due to nudge, in minutes.
    static let promiseNudgeMinutes = Key<Int>("promiseNudgeMinutes", default: 60)
    static let promisesData = Key<Data>("promisesData", default: Data())
}

/// A promise being kept track of.
struct TrackedPromise: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case open, done, dismissed }
    /// Where a follow-up message goes.
    enum Route: Codable, Equatable, Sendable {
        case whatsapp(chatJID: String)
        case messages(chatID: String)
        case none
    }

    let id: UUID
    let kind: PromiseCandidate.Kind
    var title: String
    /// Who it was made to (your promises) or by (theirs).
    let person: String
    var due: Date
    let created: Date
    let hasExplicitTime: Bool
    let route: Route
    /// "WhatsApp", "Messages", …
    let sourceName: String
    /// The message it came from.
    let quote: String
    var status: Status = .open
    var nudged = false

    var isOverdue: Bool { status == .open && due < Date() }
}

/// Watches the messages you send and receive for promises, keeps the list,
/// and nudges under the closed notch before one is due. Detection runs on
/// this Mac (PromisePolicy); nothing is sent anywhere.
@MainActor
final class PromiseKeeper: ObservableObject {
    static let shared = PromiseKeeper()

    @Published private(set) var promises: [TrackedPromise] = []
    /// The promise being nudged under the closed notch right now.
    @Published private(set) var nudge: TrackedPromise?
    /// Set when a nudge is clicked, so the Todos tab opens on the list.
    @Published var showListRequested = false

    private var timer: AnyCancellable?
    private var nudgeWork: DispatchWorkItem?
    private var started = false

    private init() {
        promises = (try? JSONDecoder().decode([TrackedPromise].self, from: Defaults[.promisesData])) ?? []
    }

    func start() {
        guard !started else { return }
        started = true
        prune()
        timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in self?.checkNudges(now: now) }
    }

    /// Open promises, soonest first.
    var open: [TrackedPromise] { promises.filter { $0.status == .open }.sorted { $0.due < $1.due } }
    var mine: [TrackedPromise] { open.filter { $0.kind == .mine } }
    var theirs: [TrackedPromise] { open.filter { $0.kind == .theirs } }

    // MARK: Watching messages

    /// Called for each message sent or received. Only recent messages count,
    /// so syncing old chats does not fill the list.
    func observe(text: String, fromMe: Bool, person: String, route: TrackedPromise.Route, sourceName: String, at date: Date) {
        guard Defaults[.enablePromiseKeeper], fromMe || Defaults[.promiseTrackTheirs] else { return }
        guard Date().timeIntervalSince(date) < 10 * 60 else { return }
        guard let found = PromisePolicy.detect(text, fromMe: fromMe, now: date) else { return }
        let title = PromisePolicy.personalized(found.title, kind: found.kind, person: person)
        // The same message can arrive twice (sent here, echoed by the phone).
        if promises.contains(where: { $0.status == .open && $0.kind == found.kind && $0.person == person
            && $0.title == title && abs($0.created.timeIntervalSince(date)) < 10 * 60 }) { return }
        let promise = TrackedPromise(id: UUID(), kind: found.kind, title: title, person: person, due: found.due,
                                     created: date, hasExplicitTime: found.hasExplicitTime, route: route,
                                     sourceName: sourceName, quote: String(text.prefix(160)))
        withAnimation(.smooth(duration: 0.25)) { promises.append(promise) }
        save()
    }

    // MARK: Actions

    func markDone(_ id: UUID) { update(id) { $0.status = .done } }
    func dismiss(_ id: UUID) { update(id) { $0.status = .dismissed } }

    /// Pushes the due time back (a day by default) and nudges again later.
    func snooze(_ id: UUID, by seconds: TimeInterval = 86_400) {
        update(id) { promise in
            promise.due = max(promise.due, Date()).addingTimeInterval(seconds)
            promise.nudged = false
        }
    }

    func draft(for promise: TrackedPromise) -> String {
        PromisePolicy.followUpDraft(kind: promise.kind, title: promise.title, person: promise.person)
    }

    func canSendFollowUp(_ promise: TrackedPromise) -> Bool {
        switch promise.route {
        case .whatsapp: return WhatsAppManager.shared.state.isConnected
        case .messages: return true
        case .none: return false
        }
    }

    /// Sends a follow-up where the promise was made. Without a route, the text
    /// is copied so it can be pasted.
    @discardableResult
    func sendFollowUp(_ text: String, for promise: TrackedPromise) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch promise.route {
        case .whatsapp(let chat):
            return await WhatsAppManager.shared.send(trimmed, to: chat)
        case .messages(let chat):
            do {
                try await AppleScriptHelper.executeVoid(NotchNotificationPolicy.messagesReplyScript(text: trimmed, chatID: chat))
                return true
            } catch {
                return false
            }
        case .none:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trimmed, forType: .string)
            return true
        }
    }

    func dismissNudge() {
        nudgeWork?.cancel()
        if nudge != nil { withAnimation(.smooth(duration: 0.25)) { nudge = nil } }
    }

    // MARK: Nudges

    private func checkNudges(now: Date) {
        guard Defaults[.enablePromiseKeeper], nudge == nil else { return }
        // A Pomodoro focus block holds nudges until the break.
        guard !FocusQuiet.shared.holds(.notification) else { return }
        let lead = TimeInterval(max(0, Defaults[.promiseNudgeMinutes]) * 60)
        guard let next = open.first(where: { !$0.nudged && now >= PromisePolicy.nudgeDate(due: $0.due, lead: lead, created: $0.created) })
        else { return }
        update(next.id) { $0.nudged = true }
        withAnimation(.smooth(duration: 0.25)) { nudge = promises.first { $0.id == next.id } }
        nudgeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissNudge() }
        nudgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    // MARK: Storage

    private func update(_ id: UUID, _ change: (inout TrackedPromise) -> Void) {
        guard let index = promises.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.smooth(duration: 0.25)) { change(&promises[index]) }
        if nudge?.id == id, promises[index].status != .open { dismissNudge() }
        save()
    }

    /// Finished promises go after a week; open ones a week after they were due.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        promises.removeAll { ($0.status != .open && $0.created < cutoff) || ($0.status == .open && $0.due < cutoff) }
        save()
    }

    func clearAll() {
        promises = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(promises) { Defaults[.promisesData] = data }
    }
}
