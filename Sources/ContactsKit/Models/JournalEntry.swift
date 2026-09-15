//
//  JournalEntry.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a write did, recorded before it happened.
public struct JournalEntry: Sendable, Equatable, Codable, Identifiable {

    /// What sort of change it was.
    public enum Operation: String, Sendable, Equatable, Codable, CaseIterable {
        case added
        case updated
        case deleted
    }

    /// Sortable and unique: the instant it was recorded, to the millisecond.
    public let id: String

    /// When it happened.
    public let date: Date

    /// What was done.
    public let operation: Operation

    /// How the contacts looked **before**. Empty for an addition, because
    /// there was nothing there.
    public let before: [Person]

    /// How they looked after. Empty for a deletion.
    public let after: [Person]

    /// What the caller said it was doing, for a person reading the log later.
    public let reason: String?

    public init(
        id: String = JournalEntry.identifier(for: Date()),
        date: Date = Date(),
        operation: Operation,
        before: [Person] = [],
        after: [Person] = [],
        reason: String? = nil
    ) {
        self.id = id
        self.date = date
        self.operation = operation
        self.before = before
        self.after = after
        self.reason = reason
    }

    /// A file-name-safe, sortable identifier for an instant.
    public static func identifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// How many contacts this entry touched.
    public var count: Int { max(before.count, after.count) }

    /// A line a person can read.
    public var summary: String {
        let names = (operation == .added ? after : before)
            .map(\.displayName)
            .filter { !$0.isEmpty }
        let who = names.isEmpty ? "\(count) contact\(count == 1 ? "" : "s")"
                                : names.joined(separator: ", ")
        return "\(operation.rawValue) \(who)"
    }
}
