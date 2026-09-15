//
//  ContactRow.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Flattening a contact into a row.
//
//  This is the part a generic table writer cannot do for you. A contact holds
//  *lists* — three phone numbers, two addresses — and a row holds cells, so
//  something has to decide what happens to the second phone number. Encoding
//  the array into the cell as JSON is lossless and unreadable; taking only the
//  first is readable and loses data.
//
//  The decision here: every value, joined, each carrying its label —
//  `mobile: +44 7700 900123 | work: +44 20 7946 0000`. Nothing is dropped, the
//  labels survive, and a person scanning a spreadsheet column can read it.
//  A caller that wants one value per column asks for `phoneNumbers` and reads
//  the model instead.
//

import Foundation

/// Turns contacts into rows of text.
public enum ContactRow {

    /// What separates several values in one cell.
    ///
    /// A pipe rather than a comma, because the cell is going into a CSV and a
    /// reader glancing at it should not have to work out which commas are
    /// separators and which are inside a value — even though the quoting makes
    /// it unambiguous to a parser.
    public static let valueSeparator = " | "

    /// The heading for each field.
    public static func headings(for fields: [ContactField]) -> [String] {
        fields.map(\.label)
    }

    /// One contact as cells, positionally matching `fields`.
    public static func cells(for person: Person, fields: [ContactField]) -> [String] {
        fields.map { cell(for: person, field: $0) }
    }

    /// One field of one contact, as text.
    public static func cell(for person: Person, field: ContactField) -> String {
        switch field {
        case .identifier: person.id
        case .givenName: person.givenName
        case .middleName: person.middleName
        case .familyName: person.familyName
        case .previousFamilyName: person.previousFamilyName
        case .namePrefix: person.namePrefix
        case .nameSuffix: person.nameSuffix
        case .nickname: person.nickname
        case .phoneticGivenName: person.phoneticGivenName
        case .phoneticMiddleName: person.phoneticMiddleName
        case .phoneticFamilyName: person.phoneticFamilyName

        case .organizationName: person.organizationName
        case .phoneticOrganizationName: person.phoneticOrganizationName
        case .departmentName: person.departmentName
        case .jobTitle: person.jobTitle

        case .phoneNumbers: join(person.phoneNumbers.map(\.described))
        case .emailAddresses: join(person.emailAddresses.map(\.described))
        case .urlAddresses: join(person.urlAddresses.map(\.described))
        case .postalAddresses:
            join(person.postalAddresses.map { labelled($0.label, $0.value.singleLine) })
        case .socialProfiles:
            join(person.socialProfiles.map { profile in
                let value = profile.value
                let name = value.username.isEmpty ? value.urlString : value.username
                return labelled(value.service.isEmpty ? profile.label : value.service, name)
            })
        case .instantMessageAddresses:
            join(person.instantMessageAddresses.map {
                labelled($0.value.service.isEmpty ? $0.label : $0.value.service, $0.value.username)
            })

        case .birthday: person.birthday?.described ?? ""
        case .nonGregorianBirthday: ""
        case .dates: join(person.dates.map { labelled($0.label, $0.value.described) })
        case .relations: join(person.relations.map { labelled($0.label, $0.value.name) })

        case .contactType: person.kind.rawValue
        case .note: person.note
        case .imageDataAvailable: person.hasImage ? "yes" : "no"

        // The bytes themselves never belong in a cell. A caller wanting the
        // picture asks for `imageData` on the model and writes a file.
        case .imageData, .thumbnailImageData:
            person.hasImage ? "(photo)" : ""
        }
    }

    /// `mobile: +44 7700 900123`, or the value alone when unlabelled.
    private static func labelled(_ label: String?, _ value: String) -> String {
        guard let label, !label.isEmpty, !value.isEmpty else { return value }
        return "\(label): \(value)"
    }

    private static func join(_ values: [String]) -> String {
        values.filter { !$0.isEmpty }.joined(separator: valueSeparator)
    }
}
