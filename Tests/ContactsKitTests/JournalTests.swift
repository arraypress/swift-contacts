//
//  JournalTests.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import ContactsKit

final class JournalTests: XCTestCase {

    private var directory: URL!
    private var journal: UndoJournal!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contacts-journal-\(UUID().uuidString)")
        journal = UndoJournal(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func person(_ name: String) -> Person {
        Person(id: name.lowercased(), givenName: name)
    }

    func testAnEntrySurvivesBeingWrittenAndRead() throws {
        let entry = JournalEntry(
            operation: .updated,
            before: [person("Ada")],
            after: [person("Ada Lovelace")],
            reason: "correcting the surname"
        )
        try journal.record(entry)

        let back = try XCTUnwrap(journal.latest())
        XCTAssertEqual(back.id, entry.id)
        XCTAssertEqual(back.operation, entry.operation)
        XCTAssertEqual(back.before, entry.before)
        XCTAssertEqual(back.after, entry.after)
        XCTAssertEqual(back.reason, "correcting the surname")

        // Timestamps are kept to the millisecond — the resolution the entry's
        // own identifier carries. Plain ISO 8601 truncates to the second, so
        // an entry did not compare equal to itself after a round trip.
        XCTAssertEqual(
            back.date.timeIntervalSince1970, entry.date.timeIntervalSince1970, accuracy: 0.001
        )
    }

    /// The directory is made on demand: a first write must not fail because
    /// nothing has ever been written.
    func testTheDirectoryIsCreatedOnDemand() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try journal.record(JournalEntry(operation: .added, after: [person("Ada")]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    /// Entries come back oldest first, because undo means "the last thing".
    func testEntriesAreChronological() async throws {
        for name in ["First", "Second", "Third"] {
            try journal.record(JournalEntry(operation: .added, after: [person(name)]))
            // The identifier is millisecond-resolution; without a gap two
            // entries written in the same millisecond would share a file name.
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let entries = try journal.entries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.first?.after.first?.givenName, "First")
        XCTAssertEqual(entries.last?.after.first?.givenName, "Third")
        XCTAssertEqual(try journal.latest()?.after.first?.givenName, "Third")
    }

    /// An undone entry is forgotten, so the same undo cannot be applied twice —
    /// the second application would be a change of its own.
    func testForgettingAnEntry() throws {
        let entry = JournalEntry(operation: .deleted, before: [person("Ada")])
        try journal.record(entry)
        XCTAssertNotNil(try journal.entry(id: entry.id))

        try journal.forget(id: entry.id)
        XCTAssertNil(try journal.entry(id: entry.id))
        XCTAssertNil(try journal.latest())

        // Forgetting something already gone is not an error.
        XCTAssertNoThrow(try journal.forget(id: entry.id))
    }

    /// This holds copies of personal data; a log that grows for ever is a
    /// liability rather than a safety net.
    func testTheOldestEntriesArePruned() throws {
        let small = UndoJournal(directory: directory, limit: 3)
        for index in 0..<6 {
            try small.record(JournalEntry(
                id: String(format: "2026-01-01-00000%d-000", index),
                operation: .added,
                after: [person("Person\(index)")]
            ))
        }
        let entries = try small.entries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.first?.after.first?.givenName, "Person3", "the oldest should have gone")
        XCTAssertEqual(entries.last?.after.first?.givenName, "Person5")
    }

    func testAnEmptyJournalIsNotAnError() throws {
        XCTAssertEqual(try journal.entries().count, 0)
        XCTAssertNil(try journal.latest())
    }

    func testTheSummaryNamesWhoItTouched() {
        let entry = JournalEntry(operation: .deleted, before: [person("Ada"), person("Grace")])
        XCTAssertEqual(entry.summary, "deleted Ada, Grace")
        XCTAssertEqual(entry.count, 2)

        let nameless = JournalEntry(operation: .added, after: [Person()])
        XCTAssertEqual(nameless.summary, "added 1 contact")
    }

    /// The identifier is the file name, so it has to sort chronologically and
    /// be legal on any file system.
    func testIdentifiersSortAndAreFileNameSafe() {
        let early = JournalEntry.identifier(for: Date(timeIntervalSince1970: 1_000_000))
        let late = JournalEntry.identifier(for: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertLessThan(early, late)
        XCTAssertFalse(early.contains(":"))
        XCTAssertFalse(early.contains("/"))
    }
}
