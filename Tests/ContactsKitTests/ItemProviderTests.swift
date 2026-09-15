//
//  ItemProviderTests.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Contacts
import XCTest
@testable import ContactsKit

final class ItemProviderTests: XCTestCase {

    private let person = Person(
        givenName: "Ada", familyName: "Lovelace",
        organizationName: "Analytical Engines",
        phoneNumbers: [Labeled(rawLabel: Labels.raw("mobile"), value: "+44 7700 900123")],
        emailAddresses: [Labeled(rawLabel: Labels.raw("work"), value: "ada@example.invalid")]
    )

    /// A dragged contact has to arrive in the other app as a contact, not as
    /// text this library and that app happened to agree on.
    func testAProviderOffersTheContactType() {
        let provider = person.itemProvider
        XCTAssertTrue(provider.canLoadObject(ofClass: CNContact.self))
        XCTAssertFalse(provider.registeredTypeIdentifiers.isEmpty)
    }

    /// Out and back in, through the system's own drag machinery.
    func testAContactSurvivesTheRoundTrip() async throws {
        let back = try await Person.from(person.itemProvider)
        let recovered = try XCTUnwrap(back)

        XCTAssertEqual(recovered.givenName, "Ada")
        XCTAssertEqual(recovered.familyName, "Lovelace")
        XCTAssertEqual(recovered.organizationName, "Analytical Engines")
        XCTAssertEqual(recovered.primaryPhone, "+44 7700 900123")
        XCTAssertEqual(recovered.primaryEmail, "ada@example.invalid")
        XCTAssertEqual(recovered.phoneNumbers.first?.label, "mobile", "the label survived too")
    }

    /// A drop is an unpredictable thing to be handed. Something that is not a
    /// contact is an ordinary answer, not an error.
    func testSomethingElseEntirelyIsNotAnError() async throws {
        let text = NSItemProvider(object: "just some text" as NSString)
        let result = try await Person.from(text)
        XCTAssertNil(result)
    }

    /// A drag of three contacts and a photograph should yield three contacts.
    func testAMixedDropKeepsWhatItCan() async {
        let providers = [
            person.itemProvider,
            NSItemProvider(object: "not a contact" as NSString),
            Person(givenName: "Grace", familyName: "Hopper").itemProvider
        ]
        let people = await Person.from(providers)
        XCTAssertEqual(people.count, 2)
        XCTAssertEqual(people.map(\.givenName).sorted(), ["Ada", "Grace"])
    }

    func testACollectionOffersOneProviderEach() {
        let people = [person, Person(givenName: "Grace")]
        XCTAssertEqual(people.itemProviders.count, 2)
    }
}
