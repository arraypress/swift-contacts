//
//  SerializationTests.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import ContactsKit

final class CSVTests: XCTestCase {

    /// RFC 4180 §2: fields with a comma, a quote or a line break are quoted,
    /// and a quote inside is doubled.
    func testQuotingFollowsTheRFC() {
        XCTAssertEqual(CSV.field("plain"), "plain")
        XCTAssertEqual(CSV.field("Smith, Jr"), "\"Smith, Jr\"")
        XCTAssertEqual(CSV.field("say \"hello\""), "\"say \"\"hello\"\"\"")
        XCTAssertEqual(CSV.field("two\nlines"), "\"two\nlines\"")
    }

    /// The bug in the app this was measured against: a name containing a comma
    /// shifted every column after it, because the row was built by
    /// interpolation with no quoting at all.
    func testANameWithACommaDoesNotShiftTheRow() {
        let csv = CSV.write(
            columns: ["Last Name", "Company"],
            rows: [["Smith, Jr", "Anthropic"]]
        )
        let rows = CSV.read(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].count, 2, "the comma became a column break")
        XCTAssertEqual(rows[1][0], "Smith, Jr")
        XCTAssertEqual(rows[1][1], "Anthropic")
    }

    /// Contact data is full of things people typed, and a spreadsheet will
    /// execute a cell that starts with `=`.
    func testFormulaInjectionIsDefused() {
        XCTAssertEqual(CSV.defuse("=SUM(A1:A9)"), "'=SUM(A1:A9)")
        XCTAssertEqual(CSV.defuse("@import"), "'@import")
        XCTAssertEqual(CSV.defuse("+1 555 0100"), "'+1 555 0100")
        // A negative number is still a number, and quoting it would break a
        // numeric column on import.
        XCTAssertEqual(CSV.defuse("-42"), "-42")
        XCTAssertEqual(CSV.defuse("Ada"), "Ada")
    }

    func testTheReaderHandlesQuotesAndNewlines() {
        let text = "a,b\r\n\"x,1\",\"y\ny\"\r\n\"say \"\"hi\"\"\",z\r\n"
        let rows = CSV.read(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1], ["x,1", "y\ny"])
        XCTAssertEqual(rows[2], ["say \"hi\"", "z"])
    }

    func testShortRowsAreSquaredAgainstTheHeader() {
        let csv = CSV.write(columns: ["a", "b", "c"], rows: [["1"]])
        XCTAssertEqual(CSV.read(csv)[1], ["1", "", ""])
    }

    func testTheDocumentEndsTheWayTheRFCSays() {
        XCTAssertTrue(CSV.write(columns: ["a"], rows: [["1"]]).hasSuffix("\r\n"))
    }
}

final class RowTests: XCTestCase {

    private let person = Person(
        givenName: "Ada", familyName: "Lovelace",
        organizationName: "Analytical Engines",
        phoneNumbers: [
            Labeled(rawLabel: Labels.raw("mobile"), value: "+44 7700 900123"),
            Labeled(rawLabel: Labels.raw("work"), value: "+44 20 7946 0000")
        ],
        emailAddresses: [Labeled(rawLabel: nil, value: "ada@example.invalid")],
        postalAddresses: [Labeled(rawLabel: Labels.raw("home"), value: PostalAddress(
            street: "12 Marylebone Road", city: "London", country: "UK"
        ))],
        birthday: DateComponentsValue(year: 1815, month: 12, day: 10)
    )

    /// Nothing is dropped. A contact with three numbers puts all three in the
    /// cell, each with its label, rather than the first one and a shrug.
    func testEveryValueSurvivesTheFlattening() {
        let cell = ContactRow.cell(for: person, field: .phoneNumbers)
        XCTAssertEqual(cell, "mobile: +44 7700 900123 | work: +44 20 7946 0000")
    }

    func testAnUnlabelledValueIsJustTheValue() {
        XCTAssertEqual(ContactRow.cell(for: person, field: .emailAddresses), "ada@example.invalid")
    }

    func testAddressesFlattenToOneLine() {
        XCTAssertEqual(
            ContactRow.cell(for: person, field: .postalAddresses),
            "home: 12 Marylebone Road, London, UK"
        )
    }

    /// Image bytes never belong in a spreadsheet cell.
    func testAPhotoBecomesAWordNotBytes() {
        var withPhoto = person
        withPhoto.hasImage = true
        XCTAssertEqual(ContactRow.cell(for: withPhoto, field: .imageData), "(photo)")
        XCTAssertEqual(ContactRow.cell(for: person, field: .imageData), "")
    }

    func testHeadingsMatchTheCells() {
        let fields: [ContactField] = [.givenName, .familyName, .phoneNumbers]
        XCTAssertEqual(ContactRow.headings(for: fields), ["First Name", "Last Name", "Phone"])
        XCTAssertEqual(ContactRow.cells(for: person, fields: fields).count, fields.count)
    }
}

final class VCardPhotoTests: XCTestCase {

    /// vCard folds at 75 octets with a leading space on continuation lines.
    /// A reader meeting an unfolded 40 KB line is entitled to reject the card,
    /// and several do.
    func testLongLinesAreFolded() {
        let line = String(repeating: "A", count: 300)
        let folded = VCardPhotos.fold(line)
        let lines = folded.components(separatedBy: "\r\n")

        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines[0].count, 75)
        for continuation in lines.dropFirst() {
            XCTAssertTrue(continuation.hasPrefix(" "), "a continuation must begin with a space")
            XCTAssertLessThanOrEqual(continuation.count, 75)
        }
        // Nothing lost in the folding.
        XCTAssertEqual(folded.replacingOccurrences(of: "\r\n ", with: ""), line)
    }

    func testShortLinesAreLeftAlone() {
        XCTAssertEqual(VCardPhotos.fold("PHOTO:abc"), "PHOTO:abc")
    }

    /// Read from the bytes rather than assumed.
    func testTheImageTypeIsSniffed() {
        XCTAssertEqual(VCardPhotos.imageType(of: Data([0xFF, 0xD8, 0xFF, 0xE0])), "JPEG")
        XCTAssertEqual(VCardPhotos.imageType(of: Data([0x89, 0x50, 0x4E, 0x47])), "PNG")
    }

    func testAPhotoPropertyIsWellFormed() {
        let property = VCardPhotos.property(for: Data([0xFF, 0xD8, 0xFF, 0x00]))
        XCTAssertNotNil(property)
        XCTAssertTrue(property!.hasPrefix("PHOTO;ENCODING=b;TYPE=JPEG:"))
        XCTAssertTrue(property!.hasSuffix("\r\n"))
        XCTAssertNil(VCardPhotos.property(for: Data()))
    }

    /// The failure mode of getting this wrong is one person's face on another
    /// person's card, so a mismatch writes no photos at all.
    func testAMismatchedCountAddsNothingRatherThanGuessing() {
        let card = Data("BEGIN:VCARD\r\nFN:A\r\nEND:VCARD\r\nBEGIN:VCARD\r\nFN:B\r\nEND:VCARD\r\n".utf8)
        let photo = Data([0xFF, 0xD8, 0xFF, 0x00])

        // One photo for two cards: refused.
        XCTAssertEqual(VCardPhotos.splice(into: card, photos: [photo]), card)

        // Two entries, one of them empty: spliced.
        let spliced = VCardPhotos.splice(into: card, photos: [photo, nil])
        let text = String(decoding: spliced, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "PHOTO").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "END:VCARD").count - 1, 2,
                       "the cards themselves must survive intact")
    }

    func testNoPhotosMeansNoChange() {
        let card = Data("BEGIN:VCARD\r\nEND:VCARD\r\n".utf8)
        XCTAssertEqual(VCardPhotos.splice(into: card, photos: [nil]), card)
    }
}

final class FormatTests: XCTestCase {

    func testFormatsKnowTheirExtensions() {
        XCTAssertEqual(ContactFormat(fileExtension: "vcf"), .vcard)
        XCTAssertEqual(ContactFormat(fileExtension: "VCARD"), .vcard)
        XCTAssertEqual(ContactFormat(fileExtension: "csv"), .csv)
        XCTAssertNil(ContactFormat(fileExtension: "txt"))
    }

    /// Worth asking before calling something a backup.
    func testCSVSaysItIsLossy() {
        XCTAssertTrue(ContactFormat.vcard.isLossless)
        XCTAssertTrue(ContactFormat.json.isLossless)
        XCTAssertFalse(ContactFormat.csv.isLossless)
    }
}
