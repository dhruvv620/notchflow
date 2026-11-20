// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import ApplicationServices

/// Replies through the WhatsApp app on this Mac, for notifications from an
/// account that isn't the one linked in Settings: opens the chat with the
/// reply typed in (WhatsApp's click-to-chat link), presses Return once
/// WhatsApp is in front, then goes back to the app you were in.
@MainActor
enum WhatsAppDesktopSender {
    private(set) static var lastError: String?

    static func send(_ text: String, phone: String) async -> Bool {
        lastError = nil
        guard let url = NotchNotificationPolicy.whatsAppSendURL(phone: phone, text: text) else {
            lastError = "That WhatsApp chat can't be opened from the notch."
            return false
        }
        guard AXIsProcessTrusted() else {
            lastError = "Allow NotchFlow in System Settings › Privacy & Security › Accessibility to send WhatsApp replies."
            return false
        }
        let previous = NSWorkspace.shared.frontmostApplication
        guard NSWorkspace.shared.open(url) else {
            lastError = "WhatsApp isn't installed on this Mac."
            return false
        }
        // Wait for WhatsApp to come to the front, then for the chat to open with the text.
        var whatsApp: NSRunningApplication?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(150))
            if let front = NSWorkspace.shared.frontmostApplication,
               let id = front.bundleIdentifier, NotchNotificationPolicy.whatsAppBundleIdentifiers.contains(id) {
                whatsApp = front
                break
            }
        }
        guard let whatsApp else {
            lastError = "WhatsApp didn't open the chat. Your reply wasn't sent."
            return false
        }
        try? await Task.sleep(for: .milliseconds(900))
        // Still WhatsApp in front: press Return in it.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == whatsApp.processIdentifier else {
            lastError = "WhatsApp lost focus before sending. Your reply is typed in the chat."
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: keyDown)?.postToPid(whatsApp.processIdentifier)
        }
        try? await Task.sleep(for: .milliseconds(350))
        if let previous, previous.processIdentifier != whatsApp.processIdentifier,
           previous.bundleIdentifier != Bundle.main.bundleIdentifier {
            previous.activate()
        }
        return true
    }
}
