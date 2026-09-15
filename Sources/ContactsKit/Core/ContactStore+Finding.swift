//
//  ContactStore+Finding.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  The ways the framework can look a contact up.
//
//  Each of these is a *store-side* predicate: the matching happens where the
//  contacts are, not by reading every card and filtering in Swift. On an
//  address book of any size that is the difference between an answer and a
//  pause, and on a phone it is the difference between a search field that
//  keeps up with typing and one that does not.
//

import Contacts
import Foundation

public extension ContactStore {

    /// Contacts with any of these identifiers.
    ///
    /// The way to turn a list of ids — from an export, a journal entry, a
    /// group — back into contacts in one round trip rather than one each.
    func contacts(
        ids: [String],
        fields: [ContactField] = ContactField.standard
    ) throws -> [Person] {
        try ensureAccess()
        guard !ids.isEmpty else { return [] }
        return try find(CNContact.predicateForContacts(withIdentifiers: ids), fields: fields)
    }

    /// Contacts with this email address.
    ///
    /// Matches the whole address, not a fragment — `predicateForContacts(matchingEmailAddress:)`
    /// is an equality test. Searching for `@example.com` finds nothing.
    func contacts(
        email: String,
        fields: [ContactField] = ContactField.standard
    ) throws -> [Person] {
        try ensureAccess()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try find(CNContact.predicateForContacts(matchingEmailAddress: trimmed), fields: fields)
    }

    /// Contacts with this phone number.
    ///
    /// **Less forgiving than it sounds**, measured against a real address
    /// book: the number as stored matches, and the same number with its spaces
    /// removed matches — but the digits alone do **not**, because stripping a
    /// leading `+` changes the number as far as the store is concerned, and
    /// neither does a trailing fragment. So this finds a number somebody
    /// pasted, and will not find one they half-remembered.
    ///
    /// | searched | matches |
    /// |---|---|
    /// | exactly as stored | yes |
    /// | spaces removed | yes |
    /// | digits only | yes, via the fallback below |
    /// | nationally, when stored internationally | yes, via the fallback below |
    /// | last seven digits | no |
    ///
    /// A caller wanting looser matching should read the numbers and compare
    /// them itself — there is no predicate for it.
    func contacts(
        phone: String,
        fields: [ContactField] = ContactField.standard
    ) throws -> [Person] {
        try ensureAccess()
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let exact = try find(
            CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: trimmed)),
            fields: fields
        )
        return exact.isEmpty ? try contactsMatchingLoosely(phone: trimmed, fields: fields) : exact
    }

    /// The fallback for a number typed in a different shape from the stored one.
    ///
    /// The store's predicate will not do this, so it is done here: read the
    /// numbers, reduce both sides to digits, and match when one ends with the
    /// other and enough digits agree. That finds `+44 7700 900123` when you
    /// typed `07700 900123`, which is the thing people actually do.
    ///
    /// Only reached when the exact search found nothing, because it walks every
    /// contact rather than asking the store — fine for an address book, wrong
    /// as a first move.
    private func contactsMatchingLoosely(
        phone: String,
        fields: [ContactField]
    ) throws -> [Person] {
        // Seven is the length of a local subscriber number in most plans:
        // shorter than that and a "match" is a coincidence.
        guard PhoneMatch.digits(phone).count >= PhoneMatch.minimumDigits else { return [] }

        var wantedFields = fields
        if !wantedFields.contains(.phoneNumbers) { wantedFields.append(.phoneNumbers) }

        var found: [Person] = []
        try enumerate(fields: wantedFields) { person in
            let matches = person.phoneNumbers.contains { PhoneMatch.same($0.value, phone) }
            if matches { found.append(person) }
        }
        return found
    }

    /// Contacts in an account.
    func contacts(
        inContainer container: String,
        fields: [ContactField] = ContactField.standard
    ) throws -> [Person] {
        try ensureAccess()
        return try find(
            CNContact.predicateForContactsInContainer(withIdentifier: container),
            fields: fields
        )
    }

    /// Runs a predicate and maps the results.
    private func find(_ predicate: NSPredicate, fields: [ContactField]) throws -> [Person] {
        var names = Set(fields.map(\.key))
        names.insert(CNContactIdentifierKey)
        do {
            return try rawStore
                .unifiedContacts(matching: predicate, keysToFetch: names.map { $0 as CNKeyDescriptor })
                .map(ContactBridge.person(from:))
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
    }
}
