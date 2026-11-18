// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Contacts

/// Looks callers up in Contacts for a photo and a number to message.
///
/// Asks for Contacts access the first time it is needed; without it, callers
/// get initials and declining with a message only works for WhatsApp calls or
/// callers shown by number.
final class ContactDirectory: @unchecked Sendable {
    static let shared = ContactDirectory()

    struct Entry: Sendable {
        let photo: Data?
        let handles: [String]
    }

    private let store = CNContactStore()
    private let queue = DispatchQueue(label: "com.dhruvv620.NotchFlow.contacts", qos: .userInitiated)
    private var cache: [String: Entry] = [:]

    func lookup(name: String) async -> Entry? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        guard await ensureAccess() else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                if let cached = self.cache[key] {
                    continuation.resume(returning: cached)
                    return
                }
                let entry = self.fetch(name: name)
                if let entry { self.cache[key] = entry }
                continuation.resume(returning: entry)
            }
        }
    }

    private func ensureAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if status == .notDetermined {
            return (try? await store.requestAccess(for: .contacts)) ?? false
        }
        return false
    }

    private func fetch(name: String) -> Entry? {
        let keys: [CNKeyDescriptor] = [
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        guard let contact = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first else { return nil }
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        let emails = contact.emailAddresses.map { String($0.value) }
        return Entry(photo: contact.thumbnailImageData, handles: phones + emails)
    }
}
