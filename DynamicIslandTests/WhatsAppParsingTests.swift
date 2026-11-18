/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import XCTest
@testable import Atoll

final class WhatsAppParsingTests: XCTestCase {
    func testJIDHelpers() {
        XCTAssertTrue(WhatsAppJID.isGroup("120363012345678901@g.us"))
        XCTAssertFalse(WhatsAppJID.isGroup("628123456789@s.whatsapp.net"))
        XCTAssertTrue(WhatsAppJID.isHidden("status@broadcast"))
        XCTAssertTrue(WhatsAppJID.isHidden("1203630@newsletter"))
        XCTAssertEqual(WhatsAppJID.user("628123:12@s.whatsapp.net"), "628123")
        XCTAssertEqual(WhatsAppJID.displayNumber("628123456789@s.whatsapp.net"), "+628123456789")
        XCTAssertTrue(WhatsAppJID.sameUser("628123:3@s.whatsapp.net", "628123@s.whatsapp.net"))
        XCTAssertFalse(WhatsAppJID.sameUser("", "628123@s.whatsapp.net"))
    }

    func testParsesGoTimestamps() {
        let plain = WhatsAppDateParser.parse("2024-01-15T10:30:00Z")
        XCTAssertEqual(plain?.timeIntervalSince1970, 1_705_314_600)

        // Go prints up to nine fractional digits; the formatter only takes three.
        let nanos = WhatsAppDateParser.parse("2024-01-15T10:30:00.123456789Z")
        XCTAssertEqual(nanos?.timeIntervalSince1970 ?? 0, 1_705_314_600.123, accuracy: 0.001)

        let offset = WhatsAppDateParser.parse("2024-01-15T17:30:00.5+07:00")
        XCTAssertEqual(offset?.timeIntervalSince1970 ?? 0, 1_705_314_600.5, accuracy: 0.001)

        XCTAssertNil(WhatsAppDateParser.parse(""))
        XCTAssertNil(WhatsAppDateParser.parse(nil))
    }

    func testDecodesChatAndMessageLists() throws {
        let chats = try JSONDecoder().decode(GOWAResponse<GOWAChatList>.self, from: Data(#"""
        {"code":"SUCCESS","message":"ok","results":{"data":[
          {"jid":"628123@s.whatsapp.net","name":"Selene","last_message_time":"2024-01-15T10:30:00Z","archived":false}
        ],"pagination":{"limit":25,"offset":0,"total":1}}}
        """#.utf8))
        XCTAssertEqual(chats.results?.data?.first?.name, "Selene")

        let messages = try JSONDecoder().decode(GOWAResponse<GOWAMessageList>.self, from: Data(#"""
        {"code":"SUCCESS","results":{"data":[
          {"id":"ABC","chat_jid":"628123@s.whatsapp.net","sender_jid":"628123@s.whatsapp.net",
           "sender_display_name":"Selene","content":"","timestamp":"2024-01-15T10:30:00Z",
           "is_from_me":false,"media_type":"image","filename":null}
        ]}}
        """#.utf8))
        let message = try XCTUnwrap(messages.results?.data?.first).toMessage(fallbackChatJID: "x")
        XCTAssertEqual(message.chatJID, "628123@s.whatsapp.net")
        XCTAssertEqual(message.senderName, "Selene")
        XCTAssertEqual(message.previewText, WhatsAppMessage.label(forMediaType: "image", filename: nil))
    }

    func testReadsWebhookMessageEvents() throws {
        let text = try XCTUnwrap(WhatsAppWebhookEvent(data: Data(#"""
        {"event":"message","device_id":"628987@s.whatsapp.net","payload":{
          "id":"3EB0","chat_id":"120363@g.us","from":"628123@s.whatsapp.net",
          "sender_display_name":"Saved Contact","from_name":"John","timestamp":"2023-10-15T10:36:00Z",
          "is_from_me":false,"body":"@628987 can you check this?","mentions":["628987@s.whatsapp.net"]}}
        """#.utf8)))
        XCTAssertEqual(text.event, "message")
        let message = try XCTUnwrap(text.message())
        XCTAssertEqual(message.senderName, "Saved Contact")
        XCTAssertEqual(message.text, "@628987 can you check this?")
        XCTAssertEqual(text.strings("mentions"), ["628987@s.whatsapp.net"])

        let image = try XCTUnwrap(WhatsAppWebhookEvent(data: Data(#"""
        {"event":"message","payload":{"id":"1","chat_id":"628123@s.whatsapp.net","from":"628123@s.whatsapp.net",
          "timestamp":"2025-07-13T11:05:51Z","image":{"url":"https://example.invalid/x"}}}
        """#.utf8)))
        XCTAssertEqual(image.message()?.mediaType, "image")

        let document = try XCTUnwrap(WhatsAppWebhookEvent(data: Data(#"""
        {"event":"message","payload":{"id":"2","chat_id":"628123@s.whatsapp.net",
          "document":{"filename":"invoice.pdf"}}}
        """#.utf8)))
        XCTAssertEqual(document.message()?.filename, "invoice.pdf")

        XCTAssertNil(WhatsAppWebhookEvent(data: Data("not json".utf8)))
    }

    func testFindsReleaseChecksum() {
        let checksums = """
        0123abcd  whatsapp_9.10.0_darwin_amd64.zip
        89efcdab *whatsapp_9.10.0_darwin_arm64.zip
        """
        XCTAssertEqual(
            WhatsAppGatewayInstaller.expectedChecksum(in: checksums, for: "whatsapp_9.10.0_darwin_arm64.zip"),
            "89efcdab"
        )
        XCTAssertNil(WhatsAppGatewayInstaller.expectedChecksum(in: checksums, for: "whatsapp_9.10.0_linux_arm64.zip"))
    }

    func testShortTimeFormatting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(WhatsAppTimeFormatter.short(now.addingTimeInterval(-6 * 60), now: now), "6m")
        XCTAssertEqual(WhatsAppTimeFormatter.short(now.addingTimeInterval(-22 * 3600), now: now), "22h")
        XCTAssertEqual(WhatsAppTimeFormatter.short(now.addingTimeInterval(-86_400), now: now), "1d")
    }
}
