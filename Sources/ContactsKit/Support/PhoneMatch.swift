//
//  PhoneMatch.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Deciding whether two written phone numbers are the same number.
//

import Foundation

/// Comparing phone numbers as people actually type them.
///
/// The same number is stored one way and remembered another: `+44 7700 900123`
/// on the card, `07700 900123` in somebody's head. A comparison that asks
/// whether one string ends with the other gets that pair **wrong** — the
/// national trunk `0` replaces the country code `44` rather than sitting
/// beside it, so neither is a suffix of the other:
///
/// ```
///   447700900123   stored, digits only
///   07700900123    typed, digits only
/// ```
///
/// Comparing the last nine digits gets it right, and nine is chosen rather
/// than guessed: subscriber numbers are seven to nine digits in the plans this
/// runs against, so nine is the longest tail that two different numbers are
/// unlikely to share while still being short enough to survive any prefix a
/// country puts in front of it.
///
/// This is **not** a phone number parser. It does not know dialling plans,
/// does not normalise, and is not safe for deciding that two contacts are the
/// same person. It answers one question — "did they mean this one?" — well
/// enough to act on, and every caller here confirms the answer by name before
/// changing anything.
public enum PhoneMatch {

    /// How many trailing digits decide a match.
    public static let significantDigits = 9

    /// Below this, only an exact match counts.
    ///
    /// Seven is the length of a local subscriber number in most plans. Shorter
    /// than that — a short code, an extension — and a shared tail is a
    /// coincidence rather than a match.
    public static let minimumDigits = 7

    /// Whether two written numbers are plausibly the same number.
    public static func same(_ one: String, _ other: String) -> Bool {
        let a = digits(one)
        let b = digits(other)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }

        // A short number has no room to differ in how it was written, so
        // anything other than equality is a different number.
        guard a.count >= minimumDigits, b.count >= minimumDigits else { return false }

        let length = min(a.count, b.count, significantDigits)
        return a.suffix(length) == b.suffix(length)
    }

    /// The digits of a written number, punctuation and spacing discarded.
    public static func digits(_ value: String) -> String {
        value.filter(\.isNumber)
    }
}
