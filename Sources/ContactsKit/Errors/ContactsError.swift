//
//  ContactsError.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why a contacts operation could not be carried out.
public enum ContactsError: Error, Equatable, Sendable, LocalizedError {

    /// Nobody has been asked for permission yet.
    case notDetermined

    /// The user said no, or a policy says no.
    ///
    /// There is no way to ask again from code: once denied, the only route is
    /// System Settings ▸ Privacy & Security ▸ Contacts. An error that says so
    /// is more use than one that says "denied".
    case denied

    /// Reading notes without the entitlement Apple grants by request.
    case notesNotEntitled

    /// No contact with that identifier, or it has since been deleted.
    case notFound(String)

    /// The store refused a write.
    case writeFailed(String)

    /// The store refused a read.
    case readFailed(String)

    /// A vCard, CSV or JSON that could not be understood.
    case cannotParse(String)

    public var errorDescription: String? {
        switch self {
        case .notDetermined:
            "Contacts access has not been granted yet"
        case .denied:
            "Contacts access is denied — System Settings ▸ Privacy & Security ▸ Contacts"
        case .notesNotEntitled:
            "Notes need Apple's com.apple.developer.contacts.notes entitlement — "
                + "reading one throws, and writing one fails the whole save"
        case .notFound(let id):
            "No contact with identifier \(id)"
        case .writeFailed(let reason):
            "Could not write to Contacts: \(reason)"
        case .readFailed(let reason):
            "Could not read Contacts: \(reason)"
        case .cannotParse(let reason):
            "Could not read that file: \(reason)"
        }
    }
}

/// Whether this process may read contacts.
public enum ContactAuthorization: String, Sendable, Equatable, CaseIterable {

    case notDetermined
    case restricted
    case denied
    case authorized

    /// Some contacts, chosen by the user. **iOS 18 and later only** — macOS has
    /// no such state, so a tool written against it there will never see this.
    case limited

    /// Whether any reading is possible at all.
    public var canRead: Bool { self == .authorized || self == .limited }
}
