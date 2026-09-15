//
//  ContactStore+Writing.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Changing the address book, and being able to change it back.
//

import Contacts
import Foundation

public extension ContactStore {

    // MARK: - Adding

    /// Saves a new contact and returns it with the identifier the store gave it.
    ///
    /// - Parameters:
    ///   - person: The contact to create. Its ``Person/id`` is ignored — the
    ///     store issues one.
    ///   - container: Which account to put it in, or `nil` for the default.
    ///   - journal: Recorded before the write, so the addition can be undone.
    ///   - reason: A line for whoever reads the log later.
    @discardableResult
    ///   - writeNote: Whether to write ``Person/note``. Needs Apple's notes
    ///     entitlement; without it the **whole save fails**, so this is off
    ///     unless a caller knows it has one.
    func add(
        _ person: Person,
        toContainer container: String? = nil,
        journal: UndoJournal? = nil,
        reason: String? = nil,
        writeNote: Bool = false
    ) throws -> Person {
        try ensureAccess()

        let contact = ContactBridge.mutable(from: person, includeNote: writeNote)
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: container)

        try execute(request)

        var saved = person
        saved.id = contact.identifier
        // Recorded AFTER the write for an addition, because what has to be
        // undone is the thing that now exists — and until it exists there is
        // no identifier to undo it by.
        try journal?.record(JournalEntry(operation: .added, after: [saved], reason: reason))
        return saved
    }

    // MARK: - Updating

    /// Writes changes to an existing contact.
    ///
    /// The contact is re-fetched first and edited in place. That is not
    /// belt-and-braces: `CNSaveRequest` writes the **whole** record, so saving
    /// a freshly-built object blanks every field it does not carry. An update
    /// of a job title assembled from a partial read is how a phone number
    /// disappears, quietly, and it is the single most dangerous thing this
    /// file does.
    ///
    /// - Parameters:
    ///   - person: The contact, carrying the identifier it was read with.
    ///   - journal: Recorded **before** the write, holding the contact as it
    ///     was. This throws if it cannot be written, and the update does not
    ///     happen.
    func update(
        _ person: Person,
        journal: UndoJournal? = nil,
        reason: String? = nil,
        writeNote: Bool = false
    ) throws {
        try ensureAccess()
        guard !person.id.isEmpty else {
            throw ContactsError.writeFailed("that contact has no identifier — add it instead")
        }

        // Every key, because the record is rewritten whole and anything not
        // fetched here would be written back empty.
        let keys = ContactField.allCases.filter { !$0.isEntitled }
        let existing = try fetchForEditing(id: person.id, fields: keys)

        try journal?.record(JournalEntry(
            operation: .updated,
            before: [ContactBridge.person(from: existing)],
            after: [person],
            reason: reason
        ))

        let contact = ContactBridge.mutable(from: person, existing: existing, includeNote: writeNote)
        let request = CNSaveRequest()
        request.update(contact)
        try execute(request)
    }

    // MARK: - Deleting

    /// Removes a contact.
    ///
    /// - Note: Undoing a deletion puts the contact back with a **new**
    ///   identifier. The store does not let a caller choose one, so anything
    ///   holding the old identifier — another tool's notes, a saved list —
    ///   will not find it again. Worth saying out loud before deleting in bulk.
    func delete(
        id: String,
        journal: UndoJournal? = nil,
        reason: String? = nil
    ) throws {
        try ensureAccess()
        let keys = ContactField.allCases.filter { !$0.isEntitled }
        let existing = try fetchForEditing(id: id, fields: keys)

        try journal?.record(JournalEntry(
            operation: .deleted,
            before: [ContactBridge.person(from: existing)],
            reason: reason
        ))

        guard let mutable = existing.mutableCopy() as? CNMutableContact else {
            throw ContactsError.writeFailed("could not prepare \(id) for deletion")
        }
        let request = CNSaveRequest()
        request.delete(mutable)
        try execute(request)
    }

    // MARK: - Undo

    /// Puts back what an entry changed.
    ///
    /// - Returns: What it did, in words, for the caller to report.
    /// - Note: The entry is forgotten afterwards, so the same undo cannot be
    ///   applied twice — the second application would be a change of its own.
    @discardableResult
    func undo(_ entry: JournalEntry, journal: UndoJournal? = nil) throws -> String {
        try ensureAccess()

        switch entry.operation {
        case .added:
            for person in entry.after where !person.id.isEmpty {
                try delete(id: person.id)
            }
            try journal?.forget(id: entry.id)
            return "removed \(entry.after.count) contact(s) that had been added"

        case .updated:
            for person in entry.before where !person.id.isEmpty {
                try update(person)
            }
            try journal?.forget(id: entry.id)
            return "restored \(entry.before.count) contact(s) to how they were"

        case .deleted:
            var restored = 0
            for person in entry.before {
                var blank = person
                blank.id = ""            // the store issues a new one
                _ = try add(blank)
                restored += 1
            }
            try journal?.forget(id: entry.id)
            return "put back \(restored) deleted contact(s), with new identifiers"
        }
    }

    // MARK: - Internals

    /// Fetches a contact with everything needed to rewrite it safely.
    private func fetchForEditing(id: String, fields: [ContactField]) throws -> CNContact {
        // Deduplicated on the key strings: `CNKeyDescriptor` is an existential
        // and cannot be put in a Set.
        var names = Set(fields.map(\.key))
        names.insert(CNContactIdentifierKey)
        let keys = names.map { $0 as CNKeyDescriptor }
        do {
            return try rawStore.unifiedContact(withIdentifier: id, keysToFetch: keys)
        } catch {
            throw ContactsError.notFound(id)
        }
    }

    /// Runs a save request, turning the framework's error into one that says
    /// what happened.
    private func execute(_ request: CNSaveRequest) throws {
        do {
            try rawStore.execute(request)
        } catch {
            let failure = error as NSError
            // The one refusal with a specific remedy, and the most opaque
            // message of any of them: "The operation couldn't be completed.
            // (Cocoa error 134092.)" is what you get for writing a note
            // without the entitlement.
            if failure.domain == NSCocoaErrorDomain, failure.code == 134092 {
                throw ContactsError.notesNotEntitled
            }
            throw ContactsError.writeFailed(failure.localizedDescription)
        }
    }
}
