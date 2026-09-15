//
//  UndoJournal.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  What was there before, written down before it stops being there.
//
//  This exists because of what the library is FOR. Editing contacts by
//  describing the edit — "give Sarah her new number", "merge the two Daves" —
//  means something other than the person is deciding which records change, and
//  the cost of it being wrong is somebody's address book. A backup taken this
//  morning is not an answer at four in the afternoon.
//
//  So every write records its own reversal first. If the journal cannot be
//  written, the write does not happen: an unrecorded change is exactly the
//  change you would want back.
//

import Foundation

/// A log of changes, each one reversible.
public struct UndoJournal: Sendable {

    /// Where entries are kept. One JSON file per entry, newest last by name.
    public let directory: URL

    /// How many entries to keep. Older ones are pruned after a successful
    /// write, oldest first.
    ///
    /// Not unlimited, because this holds copies of personal data and a log
    /// that grows for ever is a liability rather than a safety net. Not small
    /// either: the whole point is being able to go back further than you
    /// noticed.
    public let limit: Int

    public init(directory: URL, limit: Int = 200) {
        self.directory = directory
        self.limit = limit
    }

    /// ISO 8601 **with fractional seconds**.
    ///
    /// Plain `.iso8601` truncates to the second, so an entry written and read
    /// back is not equal to itself — which is a surprising thing for a record
    /// type to do, and was caught by a round-trip test. Fractional seconds
    /// keep it readable in the file *and* accurate to the millisecond, which
    /// is the resolution the entry's own identifier carries anyway.
    ///
    /// A round trip is therefore exact to the millisecond, not the microsecond.
    /// Made per use rather than shared: `ISO8601DateFormatter` is a class with
    /// mutable options and is not `Sendable`, and a journal may be written
    /// from more than one task.
    private static var timestamps: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    // MARK: - Writing

    /// Records an entry, creating the directory if it is not there.
    ///
    /// - Throws: Whatever the file system refused with. A caller **must** let
    ///   this propagate rather than carrying on: a write whose undo was not
    ///   recorded is the one nobody can put back.
    public func record(_ entry: JournalEntry) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.timestamps.string(from: date))
        }

        let url = directory.appendingPathComponent("\(entry.id).json")
        try encoder.encode(entry).write(to: url, options: .atomic)
        try prune()
    }

    /// Removes the oldest entries beyond ``limit``.
    private func prune() throws {
        let files = try urls()
        guard files.count > limit else { return }
        for url in files.prefix(files.count - limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Reading

    /// Every entry, oldest first.
    public func entries() throws -> [JournalEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.timestamps.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 instant: \(text)"
                ))
            }
            return date
        }
        return try urls().compactMap { url in
            guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
            return try? decoder.decode(JournalEntry.self, from: data)
        }
    }

    /// The most recent entry, or `nil` when nothing has been written.
    public func latest() throws -> JournalEntry? {
        try entries().last
    }

    /// One entry by its identifier.
    public func entry(id: String) throws -> JournalEntry? {
        try entries().first { $0.id == id }
    }

    /// Forgets an entry — used after it has been undone, so the same undo
    /// cannot be applied twice.
    public func forget(id: String) throws {
        let url = directory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Entry files, sorted by name — which is chronological, because the name
    /// is the timestamp.
    private func urls() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
