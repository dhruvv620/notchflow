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
    /// Also ask the AI provider about messages that might hold a promise, so
    /// Hindi, Gujarati, Marathi and mixes like Hinglish are understood.
    static let promiseUseAI = Key<Bool>("promiseUseAI", default: false)
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
/// this Mac (PromisePolicy); with "Understand any language" on, messages that
/// look like they might hold a promise also go to the user's AI provider.
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

    /// Messages waiting to be asked about, sent together a little later.
    private struct PendingMessage {
        let message: PromiseAIMessage
        let route: TrackedPromise.Route
        let sourceName: String
        let date: Date
    }
    private var pending: [PendingMessage] = []
    private var nextMessageID = 1
    private var flushWork: DispatchWorkItem?
    private var asking = false
    /// A daily cap, so a busy group chat can't run up the bill.
    private var askedToday = (day: "", count: 0)
    private static let dailyLimit = 300
    private static let batchSize = 8
    private static let batchDelay: TimeInterval = 20
    /// The last error from the AI, shown in Settings.
    @Published private(set) var aiStatus: String?

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
        if let found = PromisePolicy.detect(text, fromMe: fromMe, now: date) {
            let title = PromisePolicy.personalized(found.title, kind: found.kind, person: person)
            add(found, title: title, person: person, route: route, sourceName: sourceName, text: text, date: date)
        } else if Defaults[.promiseUseAI], AIClient.isReady(), PromiseAIPolicy.mightBePromise(text) {
            enqueue(PromiseAIMessage(id: nextMessageID, text: text, fromMe: fromMe, person: person),
                    route: route, sourceName: sourceName, date: date)
            nextMessageID += 1
        }
    }

    private func add(_ found: PromiseCandidate, title: String, person: String, route: TrackedPromise.Route,
                     sourceName: String, text: String, date: Date) {
        // The same message can arrive twice (sent here, echoed by the phone).
        if promises.contains(where: { $0.status == .open && $0.kind == found.kind && $0.person == person
            && $0.title == title && abs($0.created.timeIntervalSince(date)) < 10 * 60 }) { return }
        if promises.contains(where: { $0.status == .open && $0.person == person && $0.quote == String(text.prefix(160))
            && abs($0.created.timeIntervalSince(date)) < 10 * 60 }) { return }
        let promise = TrackedPromise(id: UUID(), kind: found.kind, title: title, person: person, due: found.due,
                                     created: date, hasExplicitTime: found.hasExplicitTime, route: route,
                                     sourceName: sourceName, quote: String(text.prefix(160)))
        withAnimation(.smooth(duration: 0.25)) { promises.append(promise) }
        save()
    }

    // MARK: Any language, with AI

    private func enqueue(_ message: PromiseAIMessage, route: TrackedPromise.Route, sourceName: String, date: Date) {
        // The same text from the same person (sent here, echoed by the phone) once.
        if pending.contains(where: { $0.message.text == message.text && $0.message.person == message.person }) { return }
        pending.append(PendingMessage(message: message, route: route, sourceName: sourceName, date: date))
        if pending.count >= Self.batchSize {
            flush()
        } else if flushWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            flushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.batchDelay, execute: work)
        }
    }

    private func flush() {
        flushWork?.cancel()
        flushWork = nil
        guard !asking, !pending.isEmpty else { return }
        let day = TimeTrackingPolicy.dayKey(Date())
        if askedToday.day != day { askedToday = (day, 0) }
        guard askedToday.count < Self.dailyLimit else {
            pending.removeAll()
            aiStatus = "Reached today's limit of \(Self.dailyLimit) messages; English promises are still found."
            return
        }
        let batch = Array(pending.prefix(Self.batchSize))
        pending.removeFirst(batch.count)
        askedToday.count += batch.count
        asking = true
        Task { @MainActor in
            defer {
                asking = false
                if !pending.isEmpty { flush() }
            }
            let now = Date()
            let messages = batch.map(\.message)
            do {
                let answer = try await AIClient.complete(system: PromiseAIPolicy.system,
                                                         user: PromiseAIPolicy.userPrompt(messages, now: now), maxTokens: 800)
                aiStatus = nil
                for found in PromiseAIPolicy.promises(fromAnswer: answer, messages: messages, now: now) {
                    guard let item = batch.first(where: { $0.message.id == found.messageID }) else { continue }
                    add(found.candidate, title: found.candidate.title, person: item.message.person, route: item.route,
                        sourceName: item.sourceName, text: item.message.text, date: item.date)
                }
            } catch {
                aiStatus = error.localizedDescription
            }
        }
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
