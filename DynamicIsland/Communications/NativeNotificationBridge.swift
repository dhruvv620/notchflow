// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Foundation

struct NotificationBridgeScan: Sendable {
    let notifications: [CommunicationNotification]
    let diagnostics: NotificationBridgeDiagnostics
}

/// Prototype for visible native Notification Center cards. All AX references
/// stay on this serial worker. No notification databases or account data are read.
final class NativeNotificationBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dhruvv620.NotchFlow.notifications-ax", qos: .utility)
    private struct Record {
        let card: AXUIElement
        let pid: pid_t
        let content: NotificationCardPolicy.Content
        let observedAt: Date
    }
    private struct Card {
        let element: AXUIElement
        let content: NotificationCardPolicy.Content
        let reply: AXUIElement?
        let editor: AXUIElement?
        let send: AXUIElement?
        let open: AXUIElement?
        let dismiss: AXUIElement?
    }
    private var records: [String: Record] = [:]
    private var firstSeen: [String: Date] = [:]

    func scan(allowedApps: Set<CommunicationApp>) async -> NotificationBridgeScan {
        guard !allowedApps.isEmpty else {
            await stop()
            return NotificationBridgeScan(
                notifications: [],
                diagnostics: NotificationBridgeDiagnostics(state: .noSources, processCount: 0, windowCount: 0,
                                                           candidateCount: 0, recognizedCount: 0)
            )
        }
        guard AXIsProcessTrusted() else {
            await stop()
            return NotificationBridgeScan(
                notifications: [],
                diagnostics: NotificationBridgeDiagnostics(state: .permissionRequired, processCount: 0,
                                                           windowCount: 0, candidateCount: 0, recognizedCount: 0)
            )
        }
        let pids = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
                .filter { !$0.isTerminated }.map(\.processIdentifier)
        }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.scanOnWorker(pids: pids, allowedApps: allowedApps)) }
        }
    }

    func perform(_ action: CommunicationNotificationAction, id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.performOnWorker(action, id: id)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.records.removeAll()
                self.firstSeen.removeAll()
                continuation.resume()
            }
        }
    }

    private func scanOnWorker(pids: [pid_t], allowedApps: Set<CommunicationApp>) -> NotificationBridgeScan {
        var next: [String: Record] = [:]
        var result: [CommunicationNotification] = []
        var windowCount = 0
        var candidateCount = 0
        let deadline = Date().addingTimeInterval(0.8)
        for pid in pids.prefix(2) where Date() < deadline {
            let windowRects = CommunicationsAX.onScreenWindowRects(pid: pid)
            guard !windowRects.isEmpty else { continue }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            let windows = CommunicationsAX.elements(application, kAXWindowsAttribute)
            windowCount += windows.count
            for window in windows.prefix(3) where Date() < deadline {
                let nodes = CommunicationsAX.snapshot(window, maxDepth: 10, maxNodes: 420,
                                                       budget: min(0.35, max(0, deadline.timeIntervalSinceNow)))
                var visitedCards = Set<CFHashCode>()

                @discardableResult
                func capture(root: Int) -> Bool {
                    guard nodes.indices.contains(root), Date() < deadline else { return false }
                    let element = nodes[root].element
                    let identity = CFHash(element)
                    guard !visitedCards.contains(identity), nodes[root].role != kAXWindowRole,
                          nodes[root].role != kAXApplicationRole,
                          CommunicationsAX.isOnScreen(element, windowRects: windowRects) else { return false }
                    visitedCards.insert(identity)
                    candidateCount += 1
                    guard let card = card(from: nodes, root: root, allowedApps: allowedApps) else { return false }
                    let identifier = String(nodes[root].identifier.prefix(2_048))
                    let nativeIdentity = identifier.isEmpty ? String(identity) : "\(identifier):\(identity)"
                    let id = NotificationCardPolicy.stableID(app: card.content.app, nativeIdentity: nativeIdentity,
                                                              sender: card.content.sender, body: card.content.body)
                    let date = firstSeen[id] ?? Date()
                    firstSeen[id] = date
                    next[id] = Record(card: element, pid: pid, content: card.content, observedAt: Date())
                    result.append(CommunicationNotification(id: id, app: card.content.app, sender: card.content.sender,
                                                            body: card.content.body, receivedAt: date,
                                                            canReply: card.reply != nil || (card.editor != nil && card.send != nil),
                                                            canOpen: card.open != nil, canDismiss: card.dismiss != nil))
                    return true
                }

                // macOS 26/27 identify banners and persistent alerts by AX
                // subrole. This is the primary path; their app name is often
                // only in the root description, not a standalone text node.
                let nativeContainers = nodes.indices.filter {
                    NotificationCardPolicy.isNotificationContainer(subrole: nodes[$0].subrole)
                }
                let nativeContainerSet = Set(nativeContainers)
                let leafContainers = nativeContainers.filter { !nodes[$0].subrole.hasSuffix("Stack") }
                for root in leafContainers where Date() < deadline { capture(root: root) }
                // A single-message stack can itself be the complete card and
                // have no nested banner/alert subrole.
                var capturedStacks = Set<Int>()
                for root in nativeContainers where nodes[root].subrole.hasSuffix("Stack") && Date() < deadline {
                    let descendants = subtreeIndices(nodes, root: root)
                    let hasLeaf = descendants.contains { $0 != root && leafContainers.contains($0) }
                    if !hasLeaf, capture(root: root) { capturedStacks.insert(root) }
                }

                // Compatibility path for older layouts that expose a source
                // label but no notification-specific subrole.
                for index in nodes.indices where Date() < deadline {
                    let node = nodes[index]
                    guard node.role == kAXStaticTextRole || node.role == kAXImageRole,
                          let label = sourceLabel(node), let app = NotificationCardPolicy.app(named: label),
                          allowedApps.contains(app) else { continue }
                    var container = node.parentIndex
                    var nearestNativeContainer: Int?
                    while let current = container {
                        if nativeContainerSet.contains(current) { nearestNativeContainer = current; break }
                        container = nodes[current].parentIndex
                    }
                    // Leaf banners were already parsed from their exact root.
                    // A successfully parsed single-card stack was too. Only
                    // fall back inside an unparsed stack, where child groups
                    // can represent separate notifications.
                    if let nearestNativeContainer,
                       !nodes[nearestNativeContainer].subrole.hasSuffix("Stack")
                        || capturedStacks.contains(nearestNativeContainer) { continue }
                    var ancestor = node.parentIndex
                    while let candidate = ancestor, Date() < deadline {
                        let before = result.count
                        capture(root: candidate)
                        if result.count > before { break }
                        ancestor = nodes[candidate].parentIndex
                    }
                }
            }
        }
        records = next
        if firstSeen.count > 128 {
            let keep = Set(firstSeen.sorted { $0.value > $1.value }.prefix(128).map(\.key))
            firstSeen = firstSeen.filter { keep.contains($0.key) }
        }
        // Matching AX identities can be reached from several source text nodes.
        var seen = Set<String>()
        let notifications = Array(result.filter { seen.insert($0.id).inserted }
            .sorted { $0.receivedAt > $1.receivedAt }.prefix(40))
        let state: NotificationBridgeDiagnostics.State
        if pids.isEmpty { state = .notificationCenterUnavailable }
        else if !notifications.isEmpty { state = .captured }
        else if candidateCount > 0 { state = .unsupportedCard }
        else { state = .waitingForBanner }
        return NotificationBridgeScan(
            notifications: notifications,
            diagnostics: NotificationBridgeDiagnostics(state: state, processCount: pids.count,
                                                       windowCount: windowCount, candidateCount: candidateCount,
                                                       recognizedCount: notifications.count)
        )
    }

    private func performOnWorker(_ action: CommunicationNotificationAction, id: String) throws {
        guard AXIsProcessTrusted(), let record = records[id], Date().timeIntervalSince(record.observedAt) < 12 else {
            throw CommunicationActionError.expired
        }
        let fresh = try validatedCard(record)
        switch action {
        case .open:
            guard let target = fresh.open else { throw CommunicationActionError.unavailable }
            try press(target)
        case .dismiss:
            guard let target = fresh.dismiss else { throw CommunicationActionError.unavailable }
            try press(target)
            records.removeValue(forKey: id)
        case .beginReply:
            if fresh.editor != nil && fresh.send != nil { return }
            guard let target = fresh.reply else { throw CommunicationActionError.unavailable }
            try press(target)
        case .sendReply(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4_000 else {
                throw CommunicationActionError.failed("Enter a reply of up to 4,000 characters.")
            }
            guard let editor = fresh.editor, fresh.send != nil else { throw CommunicationActionError.unavailable }
            guard CommunicationsAX.setValue(text, on: editor) else {
                throw CommunicationActionError.failed("The app did not expose an editable reply field. Open the conversation instead.")
            }
            // Setting AXValue can enable Send on the next native UI turn. Validate
            // the same card again, with no keyboard injection or coordinate click.
            let deadline = Date().addingTimeInterval(0.35)
            repeat {
                let current = try validatedCard(record)
                if let send = current.send, CommunicationsAX.enabled(send) {
                    try press(send)
                    records.removeValue(forKey: id)
                    return
                }
                Thread.sleep(forTimeInterval: 0.025)
            } while Date() < deadline
            throw CommunicationActionError.failed("The app has not enabled Send. Your reply was not sent; open the conversation to continue.")
        }
    }

    private func validatedCard(_ record: Record) throws -> Card {
        var pid: pid_t = 0
        guard AXUIElementGetPid(record.card, &pid) == .success, pid == record.pid,
              CommunicationsAX.isOnScreen(record.card, windowRects: CommunicationsAX.onScreenWindowRects(pid: pid)) else {
            throw CommunicationActionError.expired
        }
        let nodes = CommunicationsAX.snapshot(record.card, maxDepth: 8, maxNodes: 140, budget: 0.2)
        guard let card = card(from: nodes, root: 0, allowedApps: [record.content.app]), card.content == record.content else {
            throw CommunicationActionError.expired
        }
        return card
    }

    private func press(_ element: AXUIElement) throws {
        guard CommunicationsAX.press(element) else {
            throw CommunicationActionError.failed("The notification action is no longer available. Open the app instead.")
        }
    }

    private func card(from nodes: [CommunicationsAX.Node], root: Int,
                      allowedApps: Set<CommunicationApp>) -> Card? {
        guard nodes.indices.contains(root) else { return nil }
        let descendants = subtreeIndices(nodes, root: root)
        var texts: [String] = []
        var identifiedTexts: [NotificationCardPolicy.IdentifiedText] = []
        var imageLabels: [String] = []
        for index in descendants {
            let node = nodes[index]
            let text: String?
            if node.role == kAXStaticTextRole {
                text = staticText(node)
                if let text, !text.isEmpty {
                    identifiedTexts.append(.init(identifier: node.identifier, value: text))
                }
            }
            else if node.role == kAXImageRole {
                text = sourceLabel(node)
                imageLabels.append(contentsOf: node.labels)
            }
            else { text = nil }
            if let text, !text.isEmpty, text != texts.last { texts.append(text) }
        }
        let row = nodes[root]
        let flattenedDescription = [row.attributedDescription, row.description]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let content = NotificationCardPolicy.content(
            identifiedTexts: identifiedTexts,
            flattenedDescription: flattenedDescription,
            imageLabels: imageLabels,
            legacyStaticTexts: texts,
            allowedApps: allowedApps
        ) else { return nil }
        let buttons = descendants.map { nodes[$0] }.filter {
            ($0.role == kAXButtonRole || $0.role == kAXMenuButtonRole) && $0.actionNames.contains(kAXPressAction)
        }
        let buttonLabels = buttons.flatMap(\.labels)
        guard !NotificationCardPolicy.isCallCard(app: content.app, texts: texts, buttonLabels: buttonLabels) else { return nil }
        func button(_ kind: NotificationCardPolicy.ButtonKind, enabled: Bool = true) -> AXUIElement? {
            buttons.first { node in
                (!enabled || node.isEnabled) && node.labels.contains { NotificationCardPolicy.button($0, matches: kind) }
            }?.element
        }
        let fields = descendants.map { nodes[$0] }.filter {
            ($0.role == kAXTextFieldRole || $0.role == kAXTextAreaRole) && $0.isEnabled
                && CommunicationsAX.string($0.element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
        }
        let editor = fields.count == 1 ? fields[0].element : nil
        let nativeOpen = row.isEnabled && row.actionNames.contains(kAXPressAction) ? row.element : nil
        return Card(element: row.element, content: content, reply: button(.reply), editor: editor,
                    send: button(.send, enabled: false), open: button(.open) ?? nativeOpen,
                    dismiss: button(.dismiss))
    }

    private func subtreeIndices(_ nodes: [CommunicationsAX.Node], root: Int) -> [Int] {
        var included: Set<Int> = [root]
        var result = [root]
        for index in nodes.indices where index > root {
            if let parent = nodes[index].parentIndex, included.contains(parent) {
                included.insert(index)
                result.append(index)
            }
        }
        return result
    }
    private func sourceLabel(_ node: CommunicationsAX.Node) -> String? {
        node.labels.first { NotificationCardPolicy.app(named: $0) != nil }
    }
    private func staticText(_ node: CommunicationsAX.Node) -> String {
        [node.value, node.title, node.description].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
}
