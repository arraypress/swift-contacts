//
//  VCard.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  vCard in and out, through the system's own serialiser.
//
//  Written by hand nowhere. vCard is a deceptively awkward format — folded
//  lines at 75 octets, quoted-printable, charset parameters, three
//  incompatible versions, `;` inside a structured value versus `;` between
//  fields — and Contacts.app, iOS, Google and Outlook all read Apple's output.
//  A hand-rolled writer would be a second dialect for no gain.
//
//  The one rule that is not optional: contacts must be **fetched** with
//  `descriptorForRequiredKeys`, or serialising them fails. That is why
//  ``VCard/requiredFields`` exists and why the export path fetches its own
//  contacts rather than taking whatever a caller already had.
//

import Contacts
import Foundation

/// Reads and writes vCard data.
public enum VCard {

    /// The descriptor Apple requires for serialisation.
    ///
    /// Opaque on purpose — it is not a list of key names but a descriptor the
    /// framework resolves itself, and it changes between OS versions.
    public static var requiredDescriptor: CNKeyDescriptor {
        CNContactVCardSerialization.descriptorForRequiredKeys()
    }

    /// Turns contacts into vCard bytes.
    ///
    /// - Parameter contacts: Fetched with ``requiredDescriptor``.
    /// - Throws: ``ContactsError/writeFailed(_:)`` when the framework refuses,
    ///   which in practice means the contacts were fetched without the
    ///   required descriptor.
    static func data(from contacts: [CNContact]) throws -> Data {
        do {
            return try CNContactVCardSerialization.data(with: contacts)
        } catch {
            throw ContactsError.writeFailed(
                "vCard serialisation failed — were the contacts fetched with the required keys? "
                    + (error as NSError).localizedDescription
            )
        }
    }

    /// Reads contacts out of vCard bytes.
    public static func people(from data: Data) throws -> [Person] {
        do {
            let contacts = try CNContactVCardSerialization.contacts(with: data)
            return contacts.map(ContactBridge.person(from:))
        } catch {
            throw ContactsError.cannotParse(
                "not a vCard this system can read: \((error as NSError).localizedDescription)"
            )
        }
    }

    /// Turns values into vCard bytes, without a store.
    ///
    /// For an import round trip, or for writing a contact that was never in
    /// the address book. Note that a `Person` built here has no identifier, so
    /// what comes back out has none either.
    public static func data(from people: [Person]) throws -> Data {
        try data(from: people.map { ContactBridge.mutable(from: $0) as CNContact })
    }
}
