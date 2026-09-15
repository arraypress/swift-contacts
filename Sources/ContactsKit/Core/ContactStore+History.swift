//
//  ContactStore+History.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  What changed since last time.
//
//  The store keeps a log of its own edits and hands out a token marking a
//  place in it. Give the token back later and only what happened since comes
//  out — which is how a tool stays in step with an address book somebody else
//  is also editing, without re-reading thirty thousand cards to find the two
//  that moved.
//
//  The log is finite. Ask with a token older than the store still holds and it
//  answers with a single "drop everything" event, meaning *start again from a
//  full read*. Treating that as "nothing changed" is how a sync silently stops
//  syncing, so it is surfaced as its own case rather than folded into the rest.
//

import CContactsBridge
import Contacts
import Foundation

public extension ContactStore {

    /// A place in the change log, as of now.
    ///
    /// Read one before doing a full import, keep it, and everything after that
    /// moment is retrievable. `nil` means the store is not keeping history.
    var currentToken: ChangeToken? {
        rawStore.currentHistoryToken.map(ChangeToken.init)
    }

    /// What changed since `token`.
    ///
    /// - Parameters:
    ///   - token: Where to resume from, or `nil` for everything the log holds.
    ///   - fields: Which properties the contacts in the result carry.
    ///   - includeGroups: Whether group and membership events are reported too.
    /// - Returns: The changes, and a fresh token to resume from next time.
    func changes(
        since token: ChangeToken? = nil,
        fields: [ContactField] = ContactField.standard,
        includeGroups: Bool = true
    ) throws -> (changes: [ContactChange], token: ChangeToken?) {
        try ensureAccess()

        let request = CNChangeHistoryFetchRequest()
        request.startingToken = token?.data
        request.shouldUnifyResults = true
        request.includeGroupChanges = includeGroups
        request.additionalContactKeyDescriptors = fields.map { $0.key as CNKeyDescriptor }

        // Through the Objective-C shim: the SDK marks this API
        // NS_SWIFT_UNAVAILABLE, so there is no way to call it directly.
        var token: NSData?
        var failure: NSError?
        let events = CNKChangeHistoryEvents(rawStore, request, &token, &failure)

        guard let events else {
            throw ContactsError.readFailed(
                failure?.localizedDescription ?? "the store would not read its change history"
            )
        }

        let changes = events
            .compactMap { $0 as? CNChangeHistoryEvent }
            .compactMap(Self.change(from:))
        return (changes, (token as Data?).map(ChangeToken.init))
    }

    /// Maps one framework event onto the library's own shape.
    ///
    /// A `switch` over concrete classes rather than a protocol, because that is
    /// how the framework models it: every event is a subclass carrying
    /// different properties, and there is no common accessor to read.
    private static func change(from event: CNChangeHistoryEvent) -> ContactChange? {
        switch event {
        case is CNChangeHistoryDropEverythingEvent:
            return ContactChange(kind: .historyTruncated)

        case let event as CNChangeHistoryAddContactEvent:
            return ContactChange(
                kind: .added,
                identifier: event.contact.identifier,
                person: ContactBridge.person(from: event.contact)
            )

        case let event as CNChangeHistoryUpdateContactEvent:
            return ContactChange(
                kind: .updated,
                identifier: event.contact.identifier,
                person: ContactBridge.person(from: event.contact)
            )

        case let event as CNChangeHistoryDeleteContactEvent:
            return ContactChange(kind: .deleted, identifier: event.contactIdentifier)

        case let event as CNChangeHistoryAddGroupEvent:
            return ContactChange(kind: .groupAdded, identifier: event.group.identifier)

        case let event as CNChangeHistoryUpdateGroupEvent:
            return ContactChange(kind: .groupUpdated, identifier: event.group.identifier)

        case let event as CNChangeHistoryDeleteGroupEvent:
            return ContactChange(kind: .groupDeleted, identifier: event.groupIdentifier)

        case let event as CNChangeHistoryAddMemberToGroupEvent:
            return ContactChange(kind: .memberAdded, identifier: event.member.identifier)

        case let event as CNChangeHistoryRemoveMemberFromGroupEvent:
            return ContactChange(kind: .memberRemoved, identifier: event.member.identifier)

        default:
            // Subgroup events on macOS, and anything Apple adds later. Ignored
            // rather than guessed at.
            return nil
        }
    }
}
