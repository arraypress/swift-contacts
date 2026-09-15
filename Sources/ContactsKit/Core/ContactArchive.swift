//
//  ContactArchive.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Getting contacts out, and getting them back in.
//

import Contacts
import Foundation

/// Exports and imports contacts.
public struct ContactArchive: Sendable {

    private let store: ContactStore

    public init(store: ContactStore = ContactStore()) {
        self.store = store
    }

    // MARK: - Export

    /// Every contact, serialised.
    ///
    /// - Parameters:
    ///   - format: What to write. ``ContactFormat/vcard`` for a backup;
    ///     ``ContactFormat/csv`` for something to read.
    ///   - fields: Which columns a CSV carries. Ignored by the other two,
    ///     which always write everything they can.
    public func export(
        format: ContactFormat,
        fields: [ContactField] = ContactField.standard
    ) throws -> Data {
        switch format {
        case .vcard:
            // Fetched here rather than taken from the caller: serialisation
            // fails unless the contacts were fetched with Apple's required
            // descriptor, and that is not a thing a caller should have to know.
            let contacts = try fetchForVCard()
            let written = try VCard.data(from: contacts)
            // Apple's serialiser omits photographs entirely — see VCardPhotos.
            let photos = contacts.map { contact -> Data? in
                guard contact.isKeyAvailable(CNContactImageDataKey) else { return nil }
                return contact.imageData
            }
            return VCardPhotos.splice(into: written, photos: photos)

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            return try encoder.encode(store.all())

        case .csv:
            let people = try store.all(fields: fields)
            return Data(CSV.write(
                columns: ContactRow.headings(for: fields),
                rows: people.map { ContactRow.cells(for: $0, fields: fields) }
            ).utf8)
        }
    }

    /// Writes an export to a file, returning how many bytes it took.
    @discardableResult
    public func export(
        format: ContactFormat,
        to url: URL,
        fields: [ContactField] = ContactField.standard
    ) throws -> Int {
        let data = try export(format: format, fields: fields)
        try data.write(to: url, options: .atomic)
        return data.count
    }

    // MARK: - Import

    /// Reads contacts out of a file **without writing anything**.
    ///
    /// Separated from ``restore(_:journal:reason:)`` on purpose: seeing what a
    /// file contains and putting it into somebody's address book are different
    /// decisions, and the first should never imply the second.
    public func read(_ data: Data, format: ContactFormat) throws -> [Person] {
        switch format {
        case .vcard:
            return try VCard.people(from: data)

        case .json:
            let decoder = JSONDecoder()
            do {
                return try decoder.decode([Person].self, from: data)
            } catch {
                throw ContactsError.cannotParse("not a contacts JSON document")
            }

        case .csv:
            return try people(fromCSV: data)
        }
    }

    /// Reads a file, choosing the format from its extension.
    public func read(contentsOf url: URL) throws -> [Person] {
        guard let format = ContactFormat(fileExtension: url.pathExtension) else {
            throw ContactsError.cannotParse(
                "cannot tell what \(url.lastPathComponent) is — expected .vcf, .json or .csv"
            )
        }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw ContactsError.cannotParse("cannot read \(url.lastPathComponent)")
        }
        return try read(data, format: format)
    }

    /// Adds contacts to the address book.
    ///
    /// Every one is **added**, never merged: deciding that an incoming record
    /// is the same person as an existing one is a judgement, and making it
    /// silently during a restore is how duplicates and overwrites happen. A
    /// caller that wants merging should match on its own terms and call
    /// ``ContactStore/update(_:journal:reason:)``.
    ///
    /// - Returns: The contacts as saved, carrying their new identifiers.
    @discardableResult
    public func restore(
        _ people: [Person],
        journal: UndoJournal? = nil,
        reason: String? = nil
    ) throws -> [Person] {
        var saved: [Person] = []
        saved.reserveCapacity(people.count)
        for person in people {
            var fresh = person
            fresh.id = ""
            saved.append(try store.add(fresh))
        }
        // One entry for the whole restore, so undoing it undoes the import
        // rather than one contact of it.
        try journal?.record(JournalEntry(operation: .added, after: saved, reason: reason))
        return saved
    }

    // MARK: - Internals

    /// Contacts fetched the way vCard serialisation demands.
    private func fetchForVCard() throws -> [CNContact] {
        try store.ensureAccess()
        // The image key alongside the required descriptor: the serialiser
        // ignores it, but the splice that follows needs the bytes.
        let request = CNContactFetchRequest(keysToFetch: [
            VCard.requiredDescriptor, CNContactImageDataKey as CNKeyDescriptor
        ])
        var contacts: [CNContact] = []
        do {
            try store.rawStore.enumerateContacts(with: request) { contact, _ in
                contacts.append(contact)
            }
        } catch {
            throw ContactsError.readFailed((error as NSError).localizedDescription)
        }
        return contacts
    }

    /// Reads the CSV this library writes, by matching its headings.
    ///
    /// Only the single-valued columns are read back. A cell holding
    /// `mobile: +44 … | work: +44 …` is not parsed apart: the format was
    /// chosen for a person to read, and guessing structure back out of it
    /// would invent labels that were never written. Restoring means vCard —
    /// see ``ContactFormat/isLossless``.
    private func people(fromCSV data: Data) throws -> [Person] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ContactsError.cannotParse("that CSV is not UTF-8")
        }
        let rows = CSV.read(text)
        guard let headings = rows.first else { return [] }

        let fields = headings.map { heading in
            ContactField.allCases.first { $0.label == heading } ?? ContactField(token: heading)
        }

        return rows.dropFirst().map { row in
            var person = Person()
            for (index, field) in fields.enumerated() {
                guard let field, index < row.count else { continue }
                let value = row[index]
                guard !value.isEmpty else { continue }
                switch field {
                case .givenName: person.givenName = value
                case .middleName: person.middleName = value
                case .familyName: person.familyName = value
                case .nickname: person.nickname = value
                case .namePrefix: person.namePrefix = value
                case .nameSuffix: person.nameSuffix = value
                case .organizationName: person.organizationName = value
                case .departmentName: person.departmentName = value
                case .jobTitle: person.jobTitle = value
                case .note: person.note = value
                case .phoneNumbers:
                    person.phoneNumbers = split(value).map { Labeled(rawLabel: nil, value: $0) }
                case .emailAddresses:
                    person.emailAddresses = split(value).map { Labeled(rawLabel: nil, value: $0) }
                case .urlAddresses:
                    person.urlAddresses = split(value).map { Labeled(rawLabel: nil, value: $0) }
                default:
                    continue
                }
            }
            return person
        }
        .filter { !$0.isEmpty }
    }

    /// Splits a multi-value cell, dropping any `label: ` prefix.
    private func split(_ cell: String) -> [String] {
        cell.components(separatedBy: ContactRow.valueSeparator)
            .map { part -> String in
                guard let colon = part.firstIndex(of: ":") else { return part }
                let label = part[part.startIndex..<colon]
                // Only treat it as a label if it looks like one — a URL has a
                // colon too, and `https` is not a label.
                guard !label.contains("/"), label.count < 20 else { return part }
                return String(part[part.index(after: colon)...])
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
