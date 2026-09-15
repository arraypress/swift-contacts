//
//  PostalAddress.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Contacts
import Foundation

/// A street address, in the parts the system keeps it in.
///
/// Every field is a plain string because that is what the framework holds;
/// none of them is validated, because an address that does not fit a schema is
/// still where somebody lives.
public struct PostalAddress: Sendable, Equatable, Codable {

    public var street: String
    public var subLocality: String
    public var city: String
    public var subAdministrativeArea: String
    public var state: String
    public var postalCode: String
    public var country: String

    /// The ISO country code, where the store knows one.
    public var isoCountryCode: String

    public init(
        street: String = "",
        subLocality: String = "",
        city: String = "",
        subAdministrativeArea: String = "",
        state: String = "",
        postalCode: String = "",
        country: String = "",
        isoCountryCode: String = ""
    ) {
        self.street = street
        self.subLocality = subLocality
        self.city = city
        self.subAdministrativeArea = subAdministrativeArea
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.isoCountryCode = isoCountryCode
    }

    /// Whether every part is blank.
    public var isEmpty: Bool {
        [street, subLocality, city, subAdministrativeArea, state, postalCode, country]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The address on one line, in the order the parts are usually written.
    ///
    /// Deliberately not `CNPostalAddressFormatter`: that answers in the
    /// reader's locale and inserts newlines, which is right for a label on
    /// screen and wrong for a CSV cell or a file name. Blank parts are simply
    /// left out rather than leaving a run of commas behind them.
    public var singleLine: String {
        [street, subLocality, city, subAdministrativeArea, state, postalCode, country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

public extension PostalAddress {

    /// The address as the system would print it on an envelope.
    ///
    /// Locale-aware and **multi-line**: the order of the parts differs by
    /// country — a Japanese address runs largest-to-smallest, the opposite of
    /// a British one — and the formatter knows which. Use this for display,
    /// and ``singleLine`` for a spreadsheet cell or a file name, where a
    /// newline would break the row.
    var localized: String {
        CNPostalAddressFormatter.string(from: mutable, style: .mailingAddress)
    }
}

extension PostalAddress {

    /// Reads one out of the framework's type.
    init(_ address: CNPostalAddress) {
        self.init(
            street: address.street,
            subLocality: address.subLocality,
            city: address.city,
            subAdministrativeArea: address.subAdministrativeArea,
            state: address.state,
            postalCode: address.postalCode,
            country: address.country,
            isoCountryCode: address.isoCountryCode
        )
    }

    /// Writes one back.
    var mutable: CNMutablePostalAddress {
        let address = CNMutablePostalAddress()
        address.street = street
        address.subLocality = subLocality
        address.city = city
        address.subAdministrativeArea = subAdministrativeArea
        address.state = state
        address.postalCode = postalCode
        address.country = country
        address.isoCountryCode = isoCountryCode
        return address
    }
}
