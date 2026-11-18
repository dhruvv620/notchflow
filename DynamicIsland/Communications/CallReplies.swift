// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import Foundation

extension CommunicationsManager {
    /// Declines the call and sends the caller a short message: through the
    /// linked WhatsApp account for WhatsApp calls, otherwise through Messages
    /// to the number or address from the call or from Contacts.
    @discardableResult
    func declineWithMessage(_ text: String, callID: String) async -> Bool {
        guard let call = calls.first(where: { $0.id == callID }) else { return false }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return false }

        if call.actions.contains(.decline) {
            await performCall(.decline, id: callID)
        }

        if call.app == .whatsapp, Defaults[.enableWhatsAppFeature], WhatsAppManager.shared.state.isLinked {
            let caller = call.caller.trimmingCharacters(in: .whitespacesAndNewlines)
            if let chat = WhatsAppManager.shared.chats.first(where: {
                $0.displayName.caseInsensitiveCompare(caller) == .orderedSame
            }) {
                let sent = await WhatsAppManager.shared.send(message, to: chat.id)
                if !sent { lastError = WhatsAppManager.shared.lastSendError ?? "WhatsApp did not send the message." }
                return sent
            }
        }

        var handle = CallReplyPolicy.directHandle(from: call.caller)
        if handle == nil {
            handle = await ContactDirectory.shared.lookup(name: call.caller)?.handles.first
        }
        guard let handle else {
            lastError = "No number for \(call.caller) was found in Contacts, so the message was not sent."
            return false
        }
        do {
            try await AppleScriptHelper.executeVoid(CallReplyPolicy.messagesScript(text: message, handle: handle))
            lastError = nil
            return true
        } catch {
            lastError = "Messages did not send the reply. Allow NotchFlow to control Messages in System Settings › Privacy & Security › Automation."
            return false
        }
    }

    /// The caller's latest message from the last 15 minutes, if any.
    func recentMessage(from caller: String, now: Date = Date()) -> NotchNotification? {
        NotificationHub.shared.items.first { item in
            now.timeIntervalSince(item.date) < 15 * 60
                && CallReplyPolicy.isFromCaller(caller: caller, headline: item.headline)
        }
    }
}
