//
//  ContactFormat.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How a set of contacts is written out, or read back in.
public enum ContactFormat: String, Sendable, CaseIterable, Codable {

    /// The interchange format. Apple, Google, Outlook and every phone read it,
    /// and it is the only one of these that survives a round trip intact —
    /// which is why it is what a backup should be.
    case vcard

    /// This library's own model, as JSON. Lossless for anything it can hold,
    /// and the shape the undo journal uses.
    case json

    /// A spreadsheet. Readable by a person, and **lossy**: several phone
    /// numbers collapse into one cell, and a photograph becomes the word
    /// `(photo)`.
    case csv

    /// The usual file extension.
    public var fileExtension: String {
        switch self {
        case .vcard: "vcf"
        case .json: "json"
        case .csv: "csv"
        }
    }

    /// Whether reading this back gives you what you exported.
    ///
    /// Worth asking before calling something a backup: CSV is for reading,
    /// not for restoring.
    public var isLossless: Bool { self != .csv }

    /// Guesses from a file name.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "vcf", "vcard": self = .vcard
        case "json": self = .json
        case "csv": self = .csv
        default: return nil
        }
    }
}
