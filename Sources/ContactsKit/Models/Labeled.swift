//
//  Labeled.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Contacts
import Foundation

/// A value with the name its owner gave it — `mobile`, `work`, `home`.
///
/// The framework wraps these in `CNLabeledValue`, whose labels arrive as
/// constants like `_$!<Mobile>!$_`. That spelling is not a mistake and is not
/// safe to invent: the system localises and icons those exact strings, so a
/// contact written back with the plain word `Mobile` loses both. The raw form
/// is therefore kept, and ``label`` is the readable one — see ``Labels``.
public struct Labeled<Value: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {

    /// The label exactly as the store holds it, `_$!<Mobile>!$_` and all.
    ///
    /// `nil` where the contact never gave one, which is common and means
    /// "no label" rather than "unknown".
    public let rawLabel: String?

    /// The value itself.
    public let value: Value

    public init(rawLabel: String?, value: Value) {
        self.rawLabel = rawLabel
        self.value = value
    }

    /// The label as a person reads it: `mobile`, `work`, `home`.
    ///
    /// A label that is present but blank comes back `nil`, not `""`. Real
    /// address books hold both — measured on one — and "no label" is one
    /// thing, not two.
    public var label: String? {
        guard let rawLabel else { return nil }
        let readable = Labels.readable(rawLabel)
        return readable.isEmpty ? nil : readable
    }

    /// Whether this value carries `word` as its label, however it is spelled.
    ///
    /// Case-insensitive, because the same idea arrives spelled two ways: the
    /// framework's own `_$!<iPhone>!$_` unwraps to `iphone`, while a contact
    /// synced from Google or Exchange carries the plain string `iPhone` and is
    /// passed through untouched. Both are that label, and a caller filtering
    /// on one should not get half the answer.
    public func isLabelled(_ word: String) -> Bool {
        guard let label else { return false }
        return label.compare(word, options: .caseInsensitive) == .orderedSame
    }
}

extension Labeled where Value == String {

    /// `mobile: +44 7700 900000`, or just the value when there is no label.
    public var described: String {
        guard let label, !label.isEmpty else { return value }
        return "\(label): \(value)"
    }
}
