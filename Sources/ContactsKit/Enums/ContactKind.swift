//
//  ContactKind.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Contacts
import Foundation

/// Whether a card describes a person or an organisation.
///
/// Contacts shows the two differently — an organisation has no first and last
/// name, and its company name is the title — so a tool that writes one has to
/// say which it is or the card comes out looking wrong.
public enum ContactKind: String, Sendable, CaseIterable, Codable {

    case person
    case organization

    init(_ type: CNContactType) {
        self = type == .organization ? .organization : .person
    }

    var cnType: CNContactType {
        self == .organization ? .organization : .person
    }
}
