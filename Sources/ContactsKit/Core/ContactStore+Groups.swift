//
//  ContactStore+Groups.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Groups and the accounts they live in.
//

import Contacts
import Foundation

public extension ContactStore {

    // MARK: - Reading

    /// Every group, across every account.
    func groups() throws -> [ContactGroup] {
        try ensureAccess()
        do {
            return try rawStore.groups(matching: nil).map(ContactGroup.init)
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
    }

    /// The groups in one account.
    func groups(inContainer container: String) throws -> [ContactGroup] {
        try ensureAccess()
        do {
            return try rawStore
                .groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: container))
                .map(ContactGroup.init)
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
    }

    /// Every account contacts can live in.
    func containers() throws -> [ContactContainer] {
        try ensureAccess()
        do {
            return try rawStore.containers(matching: nil).map(ContactContainer.init)
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
    }

    /// The account a contact belongs to.
    func container(ofContact id: String) throws -> ContactContainer? {
        try ensureAccess()
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: id)
        // A contact with no container is an ordinary answer, not a failure,
        // so the store's refusal is swallowed rather than thrown.
        let found = try? rawStore.containers(matching: predicate)
        return found?.first.map(ContactContainer.init)
    }

    /// The contacts in a group.
    func members(
        ofGroup group: String,
        fields: [ContactField] = ContactField.standard
    ) throws -> [Person] {
        try ensureAccess()
        do {
            return try rawStore.unifiedContacts(
                matching: CNContact.predicateForContactsInGroup(withIdentifier: group),
                keysToFetch: fields.map { $0.key as CNKeyDescriptor }
            ).map(ContactBridge.person(from:))
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
    }

    #if os(macOS)
    /// Groups nested inside a group.
    ///
    /// macOS only — iOS has no nested groups, and the framework says so by
    /// marking the API unavailable there rather than returning nothing.
    func subgroups(ofGroup group: String) throws -> [ContactGroup] {
        try ensureAccess()
        do {
            return try rawStore
                .groups(matching: CNGroup.predicateForSubgroupsInGroup(withIdentifier: group))
                .map(ContactGroup.init)
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
    }
    #endif

    // MARK: - Writing

    /// Creates a group.
    @discardableResult
    func addGroup(
        named name: String,
        toContainer container: String? = nil,
        journal: UndoJournal? = nil
    ) throws -> ContactGroup {
        try ensureAccess()
        let group = CNMutableGroup()
        group.name = name

        let request = CNSaveRequest()
        request.add(group, toContainerWithIdentifier: container)
        try executeSave(request)

        let created = ContactGroup(id: group.identifier, name: name)
        try journal?.record(JournalEntry(
            operation: .added, reason: "created the group “\(name)”"
        ))
        return created
    }

    /// Renames a group.
    func renameGroup(id: String, to name: String) throws {
        try ensureAccess()
        guard let existing = try rawStore
            .groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first,
              let mutable = existing.mutableCopy() as? CNMutableGroup
        else { throw ContactsError.notFound(id) }

        mutable.name = name
        let request = CNSaveRequest()
        request.update(mutable)
        try executeSave(request)
    }

    /// Removes a group.
    ///
    /// - Note: This deletes the **group**, not the contacts in it. They stay
    ///   in the address book and simply stop being grouped, which is what
    ///   Contacts.app does and rarely what people fear.
    func deleteGroup(id: String) throws {
        try ensureAccess()
        guard let existing = try rawStore
            .groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first,
              let mutable = existing.mutableCopy() as? CNMutableGroup
        else { throw ContactsError.notFound(id) }

        let request = CNSaveRequest()
        request.delete(mutable)
        try executeSave(request)
    }

    /// Puts a contact in a group.
    func addMember(contact id: String, toGroup group: String) throws {
        try ensureAccess()
        let (contact, target) = try memberPair(contact: id, group: group)
        let request = CNSaveRequest()
        request.addMember(contact, to: target)
        try executeSave(request)
    }

    /// Takes a contact out of a group, leaving the contact alone.
    func removeMember(contact id: String, fromGroup group: String) throws {
        try ensureAccess()
        let (contact, target) = try memberPair(contact: id, group: group)
        let request = CNSaveRequest()
        request.removeMember(contact, from: target)
        try executeSave(request)
    }

    // MARK: - Internals

    /// The contact and group a membership change needs, or a refusal naming
    /// whichever one is missing.
    private func memberPair(contact id: String, group: String) throws -> (CNContact, CNGroup) {
        guard let found = try? rawStore.unifiedContact(
            withIdentifier: id, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
        ) else { throw ContactsError.notFound(id) }

        guard let target = try rawStore
            .groups(matching: CNGroup.predicateForGroups(withIdentifiers: [group])).first
        else { throw ContactsError.notFound(group) }

        return (found, target)
    }

    /// Runs a save request. Mirrors the one in the writing extension; kept
    /// private to each file rather than shared, because a single misplaced
    /// `internal` here would widen the write surface of the whole library.
    private func executeSave(_ request: CNSaveRequest) throws {
        do {
            try rawStore.execute(request)
        } catch {
            throw ContactsError.writeFailed((error as NSError).localizedDescription)
        }
    }
}
