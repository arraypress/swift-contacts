//
//  ContactDetails.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  The small records a contact hangs off itself: a social profile, an instant
//  message handle, a relation, a dated event.
//

import Contacts
import Foundation

/// An account on a service — Twitter, LinkedIn, Facebook.
public struct SocialProfile: Sendable, Equatable, Codable {

    /// The service's name as the store holds it: `Twitter`, `LinkedIn`.
    public var service: String

    /// The handle.
    public var username: String

    /// The service's own identifier for the account, where it has one.
    public var userIdentifier: String

    /// A link to the profile. The framework fills this in for services it
    /// knows, so it is usually present even when nobody typed it.
    public var urlString: String

    public init(service: String = "", username: String = "", userIdentifier: String = "", urlString: String = "") {
        self.service = service
        self.username = username
        self.userIdentifier = userIdentifier
        self.urlString = urlString
    }
}

/// A messaging handle — a service and a name on it.
public struct InstantMessage: Sendable, Equatable, Codable {

    /// `Skype`, `Jabber`, and so on.
    public var service: String

    /// The handle on that service.
    public var username: String

    public init(service: String = "", username: String = "") {
        self.service = service
        self.username = username
    }
}

/// Another person, named by their relationship.
///
/// The relationship itself is the *label* — `_$!<Father>!$_` — and the value
/// is their name, which is the opposite way round from how it reads. See
/// ``Labeled``.
public struct Relation: Sendable, Equatable, Codable {

    /// The related person's name.
    public var name: String

    public init(name: String = "") {
        self.name = name
    }
}

/// A date a contact keeps, other than a birthday.
///
/// Held as components rather than a `Date` because a great many of these have
/// no year: an anniversary somebody remembers as "the fourth of June" is a
/// real entry, and forcing it into a `Date` invents a year nobody gave.
public struct DateComponentsValue: Sendable, Equatable, Codable {

    public var year: Int?
    public var month: Int?
    public var day: Int?

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the parts the framework filled in, ignoring everything else.
    public init(_ components: DateComponents) {
        self.init(year: components.year, month: components.month, day: components.day)
    }

    /// The framework's type, carrying only the parts that were given.
    public var components: DateComponents {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return parts
    }

    /// `1984-06-04`, or `--06-04` where the year is unknown — the vCard
    /// spelling for a date without one, so the two agree.
    public var described: String {
        let month = self.month.map { String(format: "%02d", $0) } ?? "??"
        let day = self.day.map { String(format: "%02d", $0) } ?? "??"
        guard let year else { return "--\(month)-\(day)" }
        return String(format: "%04d-%@-%@", year, month, day)
    }

    /// Whether anything was given at all.
    public var isEmpty: Bool { year == nil && month == nil && day == nil }
}
