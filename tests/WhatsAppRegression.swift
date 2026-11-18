// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct WhatsAppRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "WhatsAppRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }

        // Chat addresses
        try require(WhatsAppJID.isGroup("120363012345678901@g.us"), "Group JID not recognized")
        try require(!WhatsAppJID.isGroup("628123456789@s.whatsapp.net"), "Personal JID treated as a group")
        try require(WhatsAppJID.isHidden("status@broadcast") && WhatsAppJID.isHidden("1203630@newsletter"), "Status/channels not hidden")
        try require(WhatsAppJID.user("628123:12@s.whatsapp.net") == "628123", "Device suffix not stripped")
        try require(WhatsAppJID.displayNumber("628123456789@s.whatsapp.net") == "+628123456789", "Phone number not formatted")
        try require(WhatsAppJID.sameUser("628123:3@s.whatsapp.net", "628123@s.whatsapp.net"), "Same account on another device not matched")
        try require(!WhatsAppJID.sameUser("", "628123@s.whatsapp.net"), "Empty JID matched an account")

        // Gateway timestamps (Go prints up to nine fractional digits)
        try require(WhatsAppDateParser.parse("2024-01-15T10:30:00Z")?.timeIntervalSince1970 == 1_705_314_600, "Plain RFC 3339 time misread")
        let nanos = WhatsAppDateParser.parse("2024-01-15T10:30:00.123456789Z")?.timeIntervalSince1970 ?? 0
        try require(abs(nanos - 1_705_314_600.123) < 0.001, "Nanosecond time misread")
        let offset = WhatsAppDateParser.parse("2024-01-15T17:30:00.5+07:00")?.timeIntervalSince1970 ?? 0
        try require(abs(offset - 1_705_314_600.5) < 0.001, "Time zone offset misread")
        try require(WhatsAppDateParser.parse("") == nil && WhatsAppDateParser.parse(nil) == nil, "Empty time parsed")

        // REST payloads
        let chats = try JSONDecoder().decode(GOWAResponse<GOWAChatList>.self, from: Data(#"""
        {"code":"SUCCESS","results":{"data":[{"jid":"628123@s.whatsapp.net","name":"Selene","last_message_time":"2024-01-15T10:30:00Z","archived":false}]}}
        """#.utf8))
        try require(chats.results?.data?.first?.name == "Selene", "Chat list not decoded")
        let messages = try JSONDecoder().decode(GOWAResponse<GOWAMessageList>.self, from: Data(#"""
        {"code":"SUCCESS","results":{"data":[{"id":"ABC","chat_jid":"628123@s.whatsapp.net","sender_jid":"628123@s.whatsapp.net","sender_display_name":"Selene","content":"","timestamp":"2024-01-15T10:30:00Z","is_from_me":false,"media_type":"image","filename":null}]}}
        """#.utf8))
        guard let stored = messages.results?.data?.first?.toMessage(fallbackChatJID: "x") else {
            throw NSError(domain: "WhatsAppRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: "Message list not decoded"])
        }
        try require(stored.chatJID == "628123@s.whatsapp.net" && stored.senderName == "Selene", "Message fields misread")
        try require(stored.previewText == WhatsAppMessage.label(forMediaType: "image", filename: nil), "Photo without caption has no label")

        // Webhook deliveries
        let mention = WhatsAppWebhookEvent(data: Data(#"""
        {"event":"message","payload":{"id":"3EB0","chat_id":"120363@g.us","from":"628123@s.whatsapp.net","sender_display_name":"Saved Contact","from_name":"John","timestamp":"2023-10-15T10:36:00Z","is_from_me":false,"body":"@628987 can you check this?","mentions":["628987@s.whatsapp.net"]}}
        """#.utf8))
        try require(mention?.event == "message", "Webhook event name lost")
        try require(mention?.message()?.senderName == "Saved Contact", "Saved contact name not preferred")
        try require(mention?.strings("mentions") == ["628987@s.whatsapp.net"], "Mentions lost")
        let image = WhatsAppWebhookEvent(data: Data(#"{"event":"message","payload":{"id":"1","chat_id":"628123@s.whatsapp.net","image":{"url":"https://example.invalid/x"}}}"#.utf8))
        try require(image?.message()?.mediaType == "image", "Image message not recognized")
        let document = WhatsAppWebhookEvent(data: Data(#"{"event":"message","payload":{"id":"2","chat_id":"628123@s.whatsapp.net","document":{"filename":"invoice.pdf"}}}"#.utf8))
        try require(document?.message()?.filename == "invoice.pdf", "Document name lost")
        try require(WhatsAppWebhookEvent(data: Data("not json".utf8)) == nil, "Garbage accepted as a webhook")

        // Gateway download verification
        let checksums = "0123abcd  whatsapp_9.10.0_darwin_amd64.zip\n89efcdab *whatsapp_9.10.0_darwin_arm64.zip\n"
        try require(WhatsAppGatewayInstaller.expectedChecksum(in: checksums, for: "whatsapp_9.10.0_darwin_arm64.zip") == "89efcdab", "Release checksum not found")
        try require(WhatsAppGatewayInstaller.expectedChecksum(in: checksums, for: "whatsapp_9.10.0_linux_arm64.zip") == nil, "Checksum returned for a missing asset")

        // Chat list ages
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try require(WhatsAppTimeFormatter.short(now.addingTimeInterval(-6 * 60), now: now) == "6m", "Minutes label wrong")
        try require(WhatsAppTimeFormatter.short(now.addingTimeInterval(-22 * 3600), now: now) == "22h", "Hours label wrong")
        try require(WhatsAppTimeFormatter.short(now.addingTimeInterval(-86_400), now: now) == "1d", "Days label wrong")

        print("WhatsApp parsing checks passed")
    }
}
