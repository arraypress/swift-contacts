//
//  ModelTests.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  The parts that need no address book. Anything touching the real store is
//  in `StoreTests`, which skips itself where there is no permission.
//

import XCTest
@testable import ContactsKit

final class FieldTests: XCTestCase {

    func testEveryFieldMapsToAFrameworkKey() {
        for field in ContactField.allCases {
            XCTAssertFalse(field.key.isEmpty, "\(field.rawValue) has no key")
            XCTAssertFalse(field.label.isEmpty, "\(field.rawValue) has no label")
        }
        let keys = ContactField.allCases.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "two fields share a framework key")
    }

    /// Notes need an entitlement Apple grants by request, and asking without
    /// it throws rather than returning empty — so a default read must not.
    func testTheDefaultReadAsksForNothingEntitledOrHuge() {
        XCTAssertFalse(ContactField.standard.contains(.note))
        XCTAssertFalse(ContactField.standard.contains(.imageData))
        XCTAssertFalse(ContactField.standard.contains(.thumbnailImageData))
        XCTAssertTrue(ContactField.standard.contains(.imageDataAvailable),
                      "knowing a photo exists is cheap and worth having")
        XCTAssertTrue(ContactField.standard.contains(.phoneNumbers))
    }

    func testTokensResolveHoweverTheyAreTyped() {
        XCTAssertEqual(ContactField(token: "givenName"), .givenName)
        XCTAssertEqual(ContactField(token: "first"), .givenName)
        XCTAssertEqual(ContactField(token: "First Name"), .givenName)
        XCTAssertEqual(ContactField(token: "company"), .organizationName)
        XCTAssertEqual(ContactField(token: "mobile"), .phoneNumbers)
        XCTAssertEqual(ContactField(token: "dob"), .birthday)
        XCTAssertNil(ContactField(token: "favourite colour"))
    }

    func testNoAliasShadowsARealFieldName() {
        let names = Set(ContactField.allCases.map { ContactField.normalise($0.rawValue) })
        for alias in ContactField.aliases.keys {
            XCTAssertFalse(names.contains(alias), "\(alias) is both an alias and a field name")
        }
    }
}

final class LabelTests: XCTestCase {

    /// `_$!<Mobile>!$_` is not a typo and cannot be trimmed: the delimiters are
    /// how the system knows to localise the label and give it an icon.
    func testTheFrameworkSpellingSurvivesARoundTrip() {
        for word in ["home", "work", "mobile", "school", "other"] {
            let raw = Labels.raw(word)
            XCTAssertTrue(raw.hasPrefix("_$!<"), "\(word) did not resolve to a framework constant")
            XCTAssertEqual(Labels.readable(raw), word)
        }
    }

    /// A label the framework does not know is a custom label, which Contacts
    /// supports and shows verbatim. Measured on a real address book, which
    /// had one reading "Italian".
    func testCustomLabelsPassThroughUntouched() {
        XCTAssertEqual(Labels.raw("Italian"), "Italian")
        XCTAssertEqual(Labels.readable("Italian"), "Italian")
    }

    /// A real address book held a label that was present but blank. "No label"
    /// should be one thing, not two.
    func testABlankLabelIsNoLabel() {
        XCTAssertNil(Labeled(rawLabel: "", value: "x").label)
        XCTAssertNil(Labeled(rawLabel: nil, value: "x").label)
        XCTAssertEqual(Labeled(rawLabel: Labels.raw("work"), value: "x").label, "work")
    }

    /// The same idea arrives spelled two ways: the framework's `_$!<iPhone>!$_`
    /// unwraps to `iphone`, while a contact synced from Google carries the
    /// plain string `iPhone`. Both are that label.
    func testMatchingALabelIgnoresHowItIsSpelled() {
        XCTAssertTrue(Labeled(rawLabel: "_$!<iPhone>!$_", value: "x").isLabelled("iphone"))
        XCTAssertTrue(Labeled(rawLabel: "iPhone", value: "x").isLabelled("iphone"))
        XCTAssertTrue(Labeled(rawLabel: "iPhone", value: "x").isLabelled("IPHONE"))
        XCTAssertFalse(Labeled(rawLabel: nil, value: "x").isLabelled("mobile"))
    }

    func testDescribedReadsAsALabelledValue() {
        XCTAssertEqual(Labeled(rawLabel: Labels.raw("mobile"), value: "+44 7700 900123").described,
                       "mobile: +44 7700 900123")
        XCTAssertEqual(Labeled(rawLabel: nil, value: "+44 7700 900123").described, "+44 7700 900123")
    }
}

final class PersonTests: XCTestCase {

    func testDisplayNameFallsBackRatherThanBeingBlank() {
        var person = Person(givenName: "Ada", familyName: "Lovelace")
        XCTAssertEqual(person.displayName, "Ada Lovelace")

        person = Person(givenName: "Ada", namePrefix: "Dr", nameSuffix: "FRS")
        XCTAssertEqual(person.displayName, "Dr Ada FRS")

        // A card with only a company is an organisation in all but the flag.
        person = Person(organizationName: "Anthropic")
        XCTAssertEqual(person.displayName, "Anthropic")

        // A card with only a number still has to be callable something.
        person = Person(phoneNumbers: [Labeled(rawLabel: nil, value: "+44 7700 900123")])
        XCTAssertEqual(person.displayName, "+44 7700 900123")

        XCTAssertEqual(Person().displayName, "")
    }

    func testAnOrganisationIsItsCompanyName() {
        let company = Person(
            kind: .organization, givenName: "ignored", organizationName: "Anthropic"
        )
        XCTAssertEqual(company.displayName, "Anthropic")
    }

    func testAPersonRoundTripsThroughJSON() throws {
        let person = Person(
            id: "ABC", givenName: "Ada", familyName: "Lovelace",
            organizationName: "Analytical Engines",
            phoneNumbers: [Labeled(rawLabel: Labels.raw("mobile"), value: "+44 7700 900123")],
            emailAddresses: [Labeled(rawLabel: Labels.raw("work"), value: "ada@example.invalid")],
            postalAddresses: [Labeled(rawLabel: Labels.raw("home"), value: PostalAddress(
                street: "12 Marylebone Road", city: "London", postalCode: "NW1 5LA", country: "UK"
            ))],
            birthday: DateComponentsValue(year: 1815, month: 12, day: 10),
            relations: [Labeled(rawLabel: Labels.raw("father"), value: Relation(name: "Byron"))]
        )
        let data = try JSONEncoder().encode(person)
        XCTAssertEqual(try JSONDecoder().decode(Person.self, from: data), person)
    }
}

final class DetailTests: XCTestCase {

    /// A great many anniversaries have no year. Forcing one into a `Date`
    /// invents a year nobody gave.
    func testADateWithoutAYearIsWrittenTheVCardWay() {
        XCTAssertEqual(DateComponentsValue(year: 1815, month: 12, day: 10).described, "1815-12-10")
        XCTAssertEqual(DateComponentsValue(month: 6, day: 4).described, "--06-04")
        XCTAssertTrue(DateComponentsValue().isEmpty)
    }

    func testAnAddressOnOneLineSkipsTheBlankParts() {
        let address = PostalAddress(street: "12 Marylebone Road", city: "London", country: "UK")
        XCTAssertEqual(address.singleLine, "12 Marylebone Road, London, UK")
        XCTAssertFalse(address.isEmpty)
        XCTAssertTrue(PostalAddress().isEmpty)
        XCTAssertEqual(PostalAddress().singleLine, "")
    }
}

// MARK: - Phone matching

/// The comparison that decides whether two written numbers are the same one.
///
/// Every case here is a shape a real number arrives in. The national-vs-
/// international pair is the one that matters: the first version of this
/// compared suffixes and got it wrong, so `--remove phone=07700900999`
/// refused to remove `+447700900999`.
final class PhoneMatchTests: XCTestCase {

    func testTheSameNumberWrittenTwoWaysMatches() {
        XCTAssertTrue(PhoneMatch.same("+44 7700 900123", "07700900123"))
        XCTAssertTrue(PhoneMatch.same("+447700900123", "07700 900123"))
        XCTAssertTrue(PhoneMatch.same("(020) 7946 0000", "+44 20 7946 0000"))
        XCTAssertTrue(PhoneMatch.same("+1 (703) 944-5362", "7039445362"))
    }

    func testPunctuationAndSpacingAreIgnored() {
        XCTAssertTrue(PhoneMatch.same("+44 7700 900123", "+44-7700-900123"))
        XCTAssertTrue(PhoneMatch.same("07700 900 123", "07700900123"))
    }

    func testDifferentNumbersDoNotMatch() {
        XCTAssertFalse(PhoneMatch.same("+447700900123", "+447700900124"))
        XCTAssertFalse(PhoneMatch.same("02079460000", "02079460001"))
    }

    func testShortNumbersOnlyMatchExactly() {
        // A shared tail between short codes is a coincidence, not a match.
        XCTAssertTrue(PhoneMatch.same("101", "101"))
        XCTAssertFalse(PhoneMatch.same("101", "8101"))
        XCTAssertFalse(PhoneMatch.same("900123", "44900123"))
    }

    func testTextWithNoDigitsNeverMatches() {
        XCTAssertFalse(PhoneMatch.same("", "07700900123"))
        XCTAssertFalse(PhoneMatch.same("not a number", "07700900123"))
    }
}
