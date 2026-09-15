//
//  ContactField.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Everything a contact can hold, as one flat list.
//
//  The framework declares thirty keys and a fetch must name the ones it wants:
//  asking for a property that was not fetched does not return nil, it **traps**
//  — `CNContact` raises rather than answering, which turns a forgotten key into
//  a crash in front of a user rather than a blank field. So the keys are
//  enumerated here, a read states what it needs, and nothing else is ever
//  touched.
//

import Contacts
import Foundation

/// A single property of a contact.
public enum ContactField: String, Sendable, CaseIterable, Codable, Hashable {

    // MARK: - Name

    /// The identifier the store knows this contact by. Always fetched.
    case identifier
    case givenName
    case middleName
    case familyName
    case previousFamilyName
    case namePrefix
    case nameSuffix
    case nickname
    case phoneticGivenName
    case phoneticMiddleName
    case phoneticFamilyName

    // MARK: - Work

    case organizationName
    case phoneticOrganizationName
    case departmentName
    case jobTitle

    // MARK: - Reaching them

    case phoneNumbers
    case emailAddresses
    case postalAddresses
    case urlAddresses
    case socialProfiles
    case instantMessageAddresses

    // MARK: - Dates and people

    case birthday
    case nonGregorianBirthday
    case dates
    case relations

    // MARK: - The rest

    /// Whether this is a person or an organisation.
    case contactType

    /// Free text.
    ///
    /// **Entitled.** Apple gates notes behind `com.apple.developer.contacts.notes`,
    /// granted by request, since iOS 13 and macOS 10.15. Fetching it without
    /// the entitlement throws rather than returning empty, so it is never
    /// included in a default read — see ``ContactField/entitled``.
    case note

    /// The full-size picture.
    case imageData

    /// The small picture the system renders in lists.
    case thumbnailImageData

    /// Whether a picture exists, without paying to load it.
    case imageDataAvailable

    // MARK: - Mapping to the framework

    /// The framework key behind this field.
    public var key: String {
        switch self {
        case .identifier: CNContactIdentifierKey
        case .givenName: CNContactGivenNameKey
        case .middleName: CNContactMiddleNameKey
        case .familyName: CNContactFamilyNameKey
        case .previousFamilyName: CNContactPreviousFamilyNameKey
        case .namePrefix: CNContactNamePrefixKey
        case .nameSuffix: CNContactNameSuffixKey
        case .nickname: CNContactNicknameKey
        case .phoneticGivenName: CNContactPhoneticGivenNameKey
        case .phoneticMiddleName: CNContactPhoneticMiddleNameKey
        case .phoneticFamilyName: CNContactPhoneticFamilyNameKey
        case .organizationName: CNContactOrganizationNameKey
        case .phoneticOrganizationName: CNContactPhoneticOrganizationNameKey
        case .departmentName: CNContactDepartmentNameKey
        case .jobTitle: CNContactJobTitleKey
        case .phoneNumbers: CNContactPhoneNumbersKey
        case .emailAddresses: CNContactEmailAddressesKey
        case .postalAddresses: CNContactPostalAddressesKey
        case .urlAddresses: CNContactUrlAddressesKey
        case .socialProfiles: CNContactSocialProfilesKey
        case .instantMessageAddresses: CNContactInstantMessageAddressesKey
        case .birthday: CNContactBirthdayKey
        case .nonGregorianBirthday: CNContactNonGregorianBirthdayKey
        case .dates: CNContactDatesKey
        case .relations: CNContactRelationsKey
        case .contactType: CNContactTypeKey
        case .note: CNContactNoteKey
        case .imageData: CNContactImageDataKey
        case .thumbnailImageData: CNContactThumbnailImageDataKey
        case .imageDataAvailable: CNContactImageDataAvailableKey
        }
    }

    /// A heading fit to print above a column.
    public var label: String {
        switch self {
        case .identifier: "ID"
        case .givenName: "First Name"
        case .middleName: "Middle Name"
        case .familyName: "Last Name"
        case .previousFamilyName: "Maiden Name"
        case .namePrefix: "Prefix"
        case .nameSuffix: "Suffix"
        case .nickname: "Nickname"
        case .phoneticGivenName: "Phonetic First Name"
        case .phoneticMiddleName: "Phonetic Middle Name"
        case .phoneticFamilyName: "Phonetic Last Name"
        case .organizationName: "Company"
        case .phoneticOrganizationName: "Phonetic Company"
        case .departmentName: "Department"
        case .jobTitle: "Job Title"
        case .phoneNumbers: "Phone"
        case .emailAddresses: "Email"
        case .postalAddresses: "Address"
        case .urlAddresses: "URL"
        case .socialProfiles: "Social Profile"
        case .instantMessageAddresses: "Instant Message"
        case .birthday: "Birthday"
        case .nonGregorianBirthday: "Birthday (Non-Gregorian)"
        case .dates: "Dates"
        case .relations: "Related People"
        case .contactType: "Type"
        case .note: "Note"
        case .imageData: "Photo"
        case .thumbnailImageData: "Thumbnail"
        case .imageDataAvailable: "Has Photo"
        }
    }

    /// Whether reading this needs an entitlement Apple grants by request.
    ///
    /// Only ``note``. Asking for it without the entitlement throws, which is
    /// why it is absent from ``ContactField/standard`` and has to be asked for
    /// deliberately.
    public var isEntitled: Bool { self == .note }

    /// Whether this field carries image bytes, which are large and rarely wanted.
    public var isImage: Bool { self == .imageData || self == .thumbnailImageData }

    /// Whether this field is part of somebody's name.
    ///
    /// Used to decide whether a fetch needs `CNContactFormatter`'s descriptor
    /// alongside it — asking for a name and not being able to format it is the
    /// case worth avoiding.
    public var isNamePart: Bool {
        switch self {
        case .givenName, .middleName, .familyName, .namePrefix, .nameSuffix,
             .nickname, .previousFamilyName, .organizationName,
             .phoneticGivenName, .phoneticMiddleName, .phoneticFamilyName:
            true
        default:
            false
        }
    }

    /// Everything worth reading by default.
    ///
    /// Excludes the entitled field and the image blobs: a folder of two
    /// thousand contacts with photographs is tens of megabytes, and almost
    /// nothing a caller does with a listing needs the pixels.
    public static var standard: [ContactField] {
        allCases.filter { !$0.isEntitled && !$0.isImage }
    }

    /// Resolves a token a person typed, ignoring case and punctuation.
    public init?(token: String) {
        let wanted = Self.normalise(token)
        guard let match = Self.allCases.first(where: { Self.normalise($0.rawValue) == wanted })
            ?? Self.aliases[wanted]
        else { return nil }
        self = match
    }

    /// Words people type for a field whose name is something else.
    static let aliases: [String: ContactField] = [
        "first": .givenName,
        "firstname": .givenName,
        "last": .familyName,
        "lastname": .familyName,
        "surname": .familyName,
        "middle": .middleName,
        "company": .organizationName,
        "organisation": .organizationName,
        "organization": .organizationName,
        "org": .organizationName,
        "title": .jobTitle,
        "role": .jobTitle,
        "phone": .phoneNumbers,
        "phones": .phoneNumbers,
        "mobile": .phoneNumbers,
        "tel": .phoneNumbers,
        "email": .emailAddresses,
        "emails": .emailAddresses,
        "mail": .emailAddresses,
        "address": .postalAddresses,
        "addresses": .postalAddresses,
        "postal": .postalAddresses,
        "url": .urlAddresses,
        "urls": .urlAddresses,
        "website": .urlAddresses,
        "social": .socialProfiles,
        "im": .instantMessageAddresses,
        "bday": .birthday,
        "dob": .birthday,
        "photo": .imageData,
        "picture": .imageData,
        "image": .imageData,
        "id": .identifier,
        "type": .contactType,
        "kind": .contactType,
        "notes": .note,

        // Singulars. Every repeating field is named in the plural by the
        // framework and typed in the singular by people — `--add date=…`
        // reads better than `--add dates=…`, and a vocabulary that refuses
        // the natural spelling is a vocabulary people have to look up.
        "date": .dates,
        "relation": .relations,
        "related": .relations,
        "profile": .socialProfiles,
        "profiles": .socialProfiles,
        "socials": .socialProfiles,
        "ims": .instantMessageAddresses,
        "chat": .instantMessageAddresses,
        "instantmessage": .instantMessageAddresses,
        "messaging": .instantMessageAddresses,

        // The rest of the card, under the words people use for it.
        "nick": .nickname,
        "prefix": .namePrefix,
        "suffix": .nameSuffix,
        "maiden": .previousFamilyName,
        "maidenname": .previousFamilyName,
        "job": .jobTitle,
        "department": .departmentName,
        "dept": .departmentName,
        "birthdate": .birthday,
        "thumbnail": .thumbnailImageData,
        "hasphoto": .imageDataAvailable
    ]

    static func normalise(_ token: String) -> String {
        token.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
