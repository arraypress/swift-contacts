//
//  ContactStore.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Reading and writing the address book.
//
//  Held as one long-lived object because `CNContactStore` is documented as
//  expensive to create and its authorization check is documented thread safe;
//  the instance is shared rather than made per call, and the class is marked
//  unchecked-Sendable on that basis rather than on a guess.
//

import Contacts
import Foundation

/// The address book.
public final class ContactStore: @unchecked Sendable {

    private let store = CNContactStore()

    /// The framework's store, for the writing half of this type.
    ///
    /// Internal rather than private only because `ContactStore+Writing` is a
    /// separate file; nothing outside the library sees it.
    var rawStore: CNContactStore { store }

    public init() {}

    // MARK: - Permission

    /// Whether this process may read contacts, without asking.
    ///
    /// Safe to call at any time and from any thread; it never prompts.
    public static var authorization: ContactAuthorization {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        #if os(iOS)
        case .limited: .limited
        #endif
        @unknown default: .denied
        }
    }

    /// Asks for permission, prompting the first time only.
    ///
    /// On a second call after a refusal this returns `false` without a prompt —
    /// the system will not ask twice, and there is no API to make it. Callers
    /// should send the user to System Settings rather than retrying.
    ///
    /// ⚠️ On macOS this **crashes a process with no `NSContactsUsageDescription`**
    /// rather than returning false. A command-line tool therefore has to embed
    /// an `Info.plist` into its binary — `-sectcreate __TEXT __info_plist` —
    /// because a bare executable has no bundle to read one from.
    @discardableResult
    public func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    /// Throws unless contacts can be read right now.
    public func ensureAccess() throws {
        switch Self.authorization {
        case .authorized, .limited: return
        case .denied, .restricted: throw ContactsError.denied
        case .notDetermined: throw ContactsError.notDetermined
        }
    }

    // MARK: - Reading

    /// Every contact, in the order the store returns them.
    ///
    /// - Parameter fields: What to fetch. Anything outside this list is not
    ///   merely absent from the result — reading it later would **trap** — so
    ///   ask for what you intend to use.
    public func all(fields: [ContactField] = ContactField.standard) throws -> [Person] {
        try ensureAccess()
        var people: [Person] = []
        try enumerate(fields: fields) { people.append($0) }
        return people
    }

    /// Walks every contact without holding them all in memory.
    ///
    /// The address book on a phone that has been in use for a decade is tens
    /// of thousands of records with photographs attached; a caller that only
    /// wants to count them, or write them out one at a time, should not have
    /// to materialise the lot first.
    public func enumerate(
        fields: [ContactField] = ContactField.standard,
        _ body: (Person) throws -> Void
    ) throws {
        try ensureAccess()
        let request = CNContactFetchRequest(keysToFetch: descriptors(for: fields))
        do {
            var thrown: Error?
            try store.enumerateContacts(with: request) { contact, stop in
                do {
                    try body(ContactBridge.person(from: contact))
                } catch {
                    thrown = error
                    stop.pointee = true
                }
            }
            if let thrown { throw thrown }
        } catch let error as ContactsError {
            throw error
        } catch {
            throw Self.readError(error, fields: fields)
        }
    }

    /// One contact by its identifier.
    public func contact(
        id: String,
        fields: [ContactField] = ContactField.standard
    ) throws -> Person {
        try ensureAccess()
        do {
            let contact = try store.unifiedContact(
                withIdentifier: id, keysToFetch: descriptors(for: fields)
            )
            return ContactBridge.person(from: contact)
        } catch {
            throw ContactsError.notFound(id)
        }
    }

    /// Contacts whose name matches `query`.
    ///
    /// Matching is the framework's own `predicateForContacts(matchingName:)`,
    /// which is what Contacts' own search field uses — it matches on parts of
    /// a name rather than as a substring, so "and" finds Andrew and not
    /// Alexander.
    public func search(
        name query: String,
        fields: [ContactField] = ContactField.standard
    ) throws -> [Person] {
        try ensureAccess()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            let found = try store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingName: trimmed),
                keysToFetch: descriptors(for: fields)
            )
            return found.map(ContactBridge.person(from:))
        } catch {
            throw Self.readError(error, fields: fields)
        }
    }

    // MARK: - Keys

    /// The fetch descriptors for a set of fields.
    ///
    /// The identifier is always included: it is how a contact read now is
    /// matched to a contact written later, and a result without it cannot be
    /// updated.
    private func descriptors(for fields: [ContactField]) -> [CNKeyDescriptor] {
        var wanted = Set(fields)
        wanted.insert(.identifier)
        var keys = wanted.map { $0.key as CNKeyDescriptor }

        // The name formatter's own requirements, whenever a name was asked
        // for. It is an opaque descriptor rather than a list of keys, and
        // without it `CNContactFormatter` reports nothing — so a Japanese
        // contact would quietly fall back to Western ordering instead of
        // being formatted at all.
        if wanted.contains(where: \.isNamePart) {
            keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))
        }
        return keys
    }

    /// Turns a framework error into one that says what to do about it.
    private static func readError(_ error: Error, fields: [ContactField]) -> ContactsError {
        let failure = error as NSError
        // Asking for notes without the entitlement is the one read failure
        // with a specific remedy, and its message otherwise says only
        // "authorization denied", which sends people to the wrong place.
        if fields.contains(.note), failure.domain == CNErrorDomain {
            return .notesNotEntitled
        }
        return .readFailed(failure.localizedDescription)
    }
}
