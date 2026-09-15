//
//  Person.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  One contact, as a value.
//
//  `CNContact` is a reference type, is not `Sendable`, is not `Codable`, and
//  traps when asked for a property that was not fetched. None of that is
//  wrong for a framework that talks to a store, and all of it is wrong for a
//  thing you want to hand between tasks, write to JSON, diff for a dry run, or
//  build from a CSV row before any store is involved.
//
//  So this is the shape everything else in the library speaks, and `CNContact`
//  exists only at the two edges where the store is actually touched.
//

import Contacts
import Foundation

/// A contact.
public struct Person: Sendable, Equatable, Codable, Identifiable {

    /// The store's identifier, empty for a contact that has not been saved yet.
    ///
    /// This is what an update is matched on, so it is the one field a caller
    /// must carry through if it intends to write the contact back.
    public var id: String

    /// Person or organisation.
    public var kind: ContactKind

    // MARK: - Name

    public var givenName: String
    public var middleName: String
    public var familyName: String
    public var previousFamilyName: String
    public var namePrefix: String
    public var nameSuffix: String
    public var nickname: String
    public var phoneticGivenName: String
    public var phoneticMiddleName: String
    public var phoneticFamilyName: String

    // MARK: - Work

    public var organizationName: String
    public var phoneticOrganizationName: String
    public var departmentName: String
    public var jobTitle: String

    // MARK: - Reaching them

    public var phoneNumbers: [Labeled<String>]
    public var emailAddresses: [Labeled<String>]
    public var postalAddresses: [Labeled<PostalAddress>]
    public var urlAddresses: [Labeled<String>]
    public var socialProfiles: [Labeled<SocialProfile>]
    public var instantMessageAddresses: [Labeled<InstantMessage>]

    // MARK: - Dates and people

    public var birthday: DateComponentsValue?
    public var dates: [Labeled<DateComponentsValue>]
    public var relations: [Labeled<Relation>]

    // MARK: - The rest

    /// Free text. Only ever populated when the entitled ``ContactField/note``
    /// was asked for — otherwise empty, which is not the same as "no note".
    public var note: String

    /// Whether the contact has a picture, which is knowable without loading it.
    public var hasImage: Bool

    /// The picture itself, only when it was asked for.
    public var imageData: Data?

    /// The name as the system itself writes it, when this contact came from
    /// the store.
    ///
    /// Not decoration. `CNContactFormatter` decides the ORDER from the
    /// contact's own script: a Japanese, Chinese, Korean or Hungarian name is
    /// family-name-first, and the joining is not always a space. Assembling
    /// the parts by hand in the Western order — which is what ``displayName``
    /// falls back to — gets those names backwards.
    ///
    /// Empty for a contact built from a CSV row or by hand, which has no
    /// script for the formatter to read.
    public var formattedName: String = ""

    public init(
        id: String = "",
        kind: ContactKind = .person,
        givenName: String = "",
        middleName: String = "",
        familyName: String = "",
        previousFamilyName: String = "",
        namePrefix: String = "",
        nameSuffix: String = "",
        nickname: String = "",
        phoneticGivenName: String = "",
        phoneticMiddleName: String = "",
        phoneticFamilyName: String = "",
        organizationName: String = "",
        phoneticOrganizationName: String = "",
        departmentName: String = "",
        jobTitle: String = "",
        phoneNumbers: [Labeled<String>] = [],
        emailAddresses: [Labeled<String>] = [],
        postalAddresses: [Labeled<PostalAddress>] = [],
        urlAddresses: [Labeled<String>] = [],
        socialProfiles: [Labeled<SocialProfile>] = [],
        instantMessageAddresses: [Labeled<InstantMessage>] = [],
        birthday: DateComponentsValue? = nil,
        dates: [Labeled<DateComponentsValue>] = [],
        relations: [Labeled<Relation>] = [],
        note: String = "",
        hasImage: Bool = false,
        imageData: Data? = nil,
        formattedName: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.previousFamilyName = previousFamilyName
        self.namePrefix = namePrefix
        self.nameSuffix = nameSuffix
        self.nickname = nickname
        self.phoneticGivenName = phoneticGivenName
        self.phoneticMiddleName = phoneticMiddleName
        self.phoneticFamilyName = phoneticFamilyName
        self.organizationName = organizationName
        self.phoneticOrganizationName = phoneticOrganizationName
        self.departmentName = departmentName
        self.jobTitle = jobTitle
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.postalAddresses = postalAddresses
        self.urlAddresses = urlAddresses
        self.socialProfiles = socialProfiles
        self.instantMessageAddresses = instantMessageAddresses
        self.birthday = birthday
        self.dates = dates
        self.relations = relations
        self.note = note
        self.hasImage = hasImage
        self.imageData = imageData
        self.formattedName = formattedName
    }

    // MARK: - Reading

    /// The name to show, chosen the way Contacts chooses it.
    ///
    /// An organisation is its company name; a person is their names joined,
    /// falling back through nickname and company so that a card with only a
    /// phone number still has something to call itself rather than showing as
    /// an empty row.
    public var displayName: String {
        // The system's answer whenever there is one: it knows the order.
        if !formattedName.isEmpty { return formattedName }
        if kind == .organization, !organizationName.isEmpty { return organizationName }

        let parts = [namePrefix, givenName, middleName, familyName, nameSuffix]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }

        for fallback in [nickname, organizationName, emailAddresses.first?.value,
                         phoneNumbers.first?.value] {
            if let fallback, !fallback.isEmpty { return fallback }
        }
        return ""
    }

    /// Whether this contact holds nothing at all.
    public var isEmpty: Bool {
        displayName.isEmpty && phoneNumbers.isEmpty && emailAddresses.isEmpty
            && postalAddresses.isEmpty && note.isEmpty
    }

    /// The first phone number, label irrespective — what a caller usually means
    /// by "their number".
    public var primaryPhone: String? { phoneNumbers.first?.value }

    /// The first email address.
    public var primaryEmail: String? { emailAddresses.first?.value }
}
