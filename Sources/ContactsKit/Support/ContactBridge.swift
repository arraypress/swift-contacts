//
//  ContactBridge.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  The two edges where `CNContact` is actually touched.
//
//  Reading is the dangerous direction. `CNContact` does not return nil for a
//  property that was not fetched — it **raises**, and an Objective-C exception
//  from a Swift value getter is not catchable: the process dies. A tool that
//  fetches five keys and later reads a sixth crashes in front of whoever is
//  using it, with a message about "A property was not requested when contact
//  was fetched".
//
//  So every read here goes through `isKeyAvailable(_:)` first. It is verbose
//  and it is the whole reason this file exists rather than a pile of direct
//  property reads at the call sites.
//

import Contacts
import Foundation

enum ContactBridge {

    // MARK: - Reading

    /// Turns a fetched contact into a value, reading only what was fetched.
    ///
    /// A field that was not requested comes back at its empty default. That is
    /// deliberately indistinguishable from a field that is genuinely empty:
    /// the alternative is an optional on all thirty properties, which pushes
    /// the distinction onto every caller for a case only the fetch knows about.
    /// Callers that care ask for the field and look.
    static func person(from contact: CNContact) -> Person {
        var person = Person(id: contact.identifier)

        if contact.isKeyAvailable(CNContactTypeKey) { person.kind = ContactKind(contact.contactType) }

        if contact.isKeyAvailable(CNContactGivenNameKey) { person.givenName = contact.givenName }
        if contact.isKeyAvailable(CNContactMiddleNameKey) { person.middleName = contact.middleName }
        if contact.isKeyAvailable(CNContactFamilyNameKey) { person.familyName = contact.familyName }
        if contact.isKeyAvailable(CNContactPreviousFamilyNameKey) {
            person.previousFamilyName = contact.previousFamilyName
        }
        if contact.isKeyAvailable(CNContactNamePrefixKey) { person.namePrefix = contact.namePrefix }
        if contact.isKeyAvailable(CNContactNameSuffixKey) { person.nameSuffix = contact.nameSuffix }
        if contact.isKeyAvailable(CNContactNicknameKey) { person.nickname = contact.nickname }
        if contact.isKeyAvailable(CNContactPhoneticGivenNameKey) {
            person.phoneticGivenName = contact.phoneticGivenName
        }
        if contact.isKeyAvailable(CNContactPhoneticMiddleNameKey) {
            person.phoneticMiddleName = contact.phoneticMiddleName
        }
        if contact.isKeyAvailable(CNContactPhoneticFamilyNameKey) {
            person.phoneticFamilyName = contact.phoneticFamilyName
        }

        if contact.isKeyAvailable(CNContactOrganizationNameKey) {
            person.organizationName = contact.organizationName
        }
        if contact.isKeyAvailable(CNContactPhoneticOrganizationNameKey) {
            person.phoneticOrganizationName = contact.phoneticOrganizationName
        }
        if contact.isKeyAvailable(CNContactDepartmentNameKey) {
            person.departmentName = contact.departmentName
        }
        if contact.isKeyAvailable(CNContactJobTitleKey) { person.jobTitle = contact.jobTitle }

        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            person.phoneNumbers = contact.phoneNumbers.map {
                Labeled(rawLabel: $0.label, value: $0.value.stringValue)
            }
        }
        if contact.isKeyAvailable(CNContactEmailAddressesKey) {
            person.emailAddresses = contact.emailAddresses.map {
                Labeled(rawLabel: $0.label, value: $0.value as String)
            }
        }
        if contact.isKeyAvailable(CNContactPostalAddressesKey) {
            person.postalAddresses = contact.postalAddresses.map {
                Labeled(rawLabel: $0.label, value: PostalAddress($0.value))
            }
        }
        if contact.isKeyAvailable(CNContactUrlAddressesKey) {
            person.urlAddresses = contact.urlAddresses.map {
                Labeled(rawLabel: $0.label, value: $0.value as String)
            }
        }
        if contact.isKeyAvailable(CNContactSocialProfilesKey) {
            person.socialProfiles = contact.socialProfiles.map {
                Labeled(rawLabel: $0.label, value: SocialProfile(
                    service: $0.value.service,
                    username: $0.value.username,
                    userIdentifier: $0.value.userIdentifier,
                    urlString: $0.value.urlString
                ))
            }
        }
        if contact.isKeyAvailable(CNContactInstantMessageAddressesKey) {
            person.instantMessageAddresses = contact.instantMessageAddresses.map {
                Labeled(rawLabel: $0.label, value: InstantMessage(
                    service: $0.value.service, username: $0.value.username
                ))
            }
        }

        if contact.isKeyAvailable(CNContactBirthdayKey), let birthday = contact.birthday {
            person.birthday = DateComponentsValue(birthday)
        }
        if contact.isKeyAvailable(CNContactDatesKey) {
            person.dates = contact.dates.map {
                Labeled(rawLabel: $0.label, value: DateComponentsValue($0.value as DateComponents))
            }
        }
        if contact.isKeyAvailable(CNContactRelationsKey) {
            person.relations = contact.contactRelations.map {
                Labeled(rawLabel: $0.label, value: Relation(name: $0.value.name))
            }
        }

        if contact.isKeyAvailable(CNContactNoteKey) { person.note = contact.note }
        if contact.isKeyAvailable(CNContactImageDataAvailableKey) {
            person.hasImage = contact.imageDataAvailable
        }
        if contact.isKeyAvailable(CNContactImageDataKey) { person.imageData = contact.imageData }

        // The system's own rendering, which knows that a Japanese name is
        // family-name-first. Guarded like everything else: the formatter reads
        // properties, and reading one that was not fetched would trap.
        if contact.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]) {
            person.formattedName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        }

        return person
    }

    // MARK: - Writing

    /// Builds a contact the store can save.
    ///
    /// - Parameters:
    ///   - person: The values to write.
    ///   - existing: The contact being updated, when there is one. An update
    ///     **must** start from the fetched object rather than a fresh
    ///     `CNMutableContact`: the framework writes back the whole record, so
    ///     saving a newly-made one blanks every field the fetch did not carry.
    ///     That is how an "update the job title" turns into "delete their
    ///     phone number", and it is silent.
    /// - Parameter includeNote: Whether to write ``Person/note``. **Off by
    ///   default, and that is not caution — it is the only thing that works.**
    ///   Writing a note without `com.apple.developer.contacts.notes` does not
    ///   drop the note: it fails the whole save with `NSCocoaErrorDomain` 134092,
    ///   so a contact that happens to carry one cannot be saved at all.
    ///   Measured by adding fields one at a time until the store refused.
    static func mutable(
        from person: Person,
        existing: CNContact? = nil,
        includeNote: Bool = false
    ) -> CNMutableContact {
        let contact = (existing?.mutableCopy() as? CNMutableContact) ?? CNMutableContact()

        contact.contactType = person.kind.cnType
        contact.givenName = person.givenName
        contact.middleName = person.middleName
        contact.familyName = person.familyName
        contact.previousFamilyName = person.previousFamilyName
        contact.namePrefix = person.namePrefix
        contact.nameSuffix = person.nameSuffix
        contact.nickname = person.nickname
        contact.phoneticGivenName = person.phoneticGivenName
        contact.phoneticMiddleName = person.phoneticMiddleName
        contact.phoneticFamilyName = person.phoneticFamilyName

        contact.organizationName = person.organizationName
        contact.phoneticOrganizationName = person.phoneticOrganizationName
        contact.departmentName = person.departmentName
        contact.jobTitle = person.jobTitle

        contact.phoneNumbers = person.phoneNumbers.map {
            CNLabeledValue(label: $0.rawLabel, value: CNPhoneNumber(stringValue: $0.value))
        }
        contact.emailAddresses = person.emailAddresses.map {
            CNLabeledValue(label: $0.rawLabel, value: $0.value as NSString)
        }
        contact.postalAddresses = person.postalAddresses.map {
            CNLabeledValue(label: $0.rawLabel, value: $0.value.mutable as CNPostalAddress)
        }
        contact.urlAddresses = person.urlAddresses.map {
            CNLabeledValue(label: $0.rawLabel, value: $0.value as NSString)
        }
        contact.socialProfiles = person.socialProfiles.map {
            CNLabeledValue(label: $0.rawLabel, value: CNSocialProfile(
                urlString: $0.value.urlString.isEmpty ? nil : $0.value.urlString,
                username: $0.value.username.isEmpty ? nil : $0.value.username,
                userIdentifier: $0.value.userIdentifier.isEmpty ? nil : $0.value.userIdentifier,
                service: $0.value.service.isEmpty ? nil : $0.value.service
            ))
        }
        contact.instantMessageAddresses = person.instantMessageAddresses.map {
            CNLabeledValue(label: $0.rawLabel, value: CNInstantMessageAddress(
                username: $0.value.username, service: $0.value.service
            ))
        }

        contact.birthday = person.birthday?.components
        contact.dates = person.dates.map {
            CNLabeledValue(label: $0.rawLabel, value: $0.value.components as NSDateComponents)
        }
        contact.contactRelations = person.relations.map {
            CNLabeledValue(label: $0.rawLabel, value: CNContactRelation(name: $0.value.name))
        }

        // Only when asked for AND present. Writing an empty note over a real
        // one — because the fetch had no entitlement to read it — would be a
        // data loss nobody asked for; writing one at all without the
        // entitlement fails the entire save.
        if includeNote, !person.note.isEmpty { contact.note = person.note }
        if let imageData = person.imageData { contact.imageData = imageData }

        return contact
    }
}
