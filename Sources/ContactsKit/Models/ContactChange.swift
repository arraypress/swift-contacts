//
//  ContactChange.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Something that happened to the address book while you were not looking.
public struct ContactChange: Sendable, Equatable, Codable {

    /// What happened.
    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        case added
        case updated
        case deleted
        case groupAdded
        case groupUpdated
        case groupDeleted
        case memberAdded
        case memberRemoved

        /// Everything before this point is unknown — the history was dropped.
        ///
        /// The store keeps a finite log. Ask with a token older than it holds
        /// and it answers with this instead, meaning "start again from a full
        /// read". Treating it as "nothing changed" is how a sync quietly
        /// stops syncing.
        case historyTruncated
    }

    public let kind: Kind

    /// The contact or group this concerns, where the event names one.
    public let identifier: String?

    /// The contact as it now is, for additions and updates.
    public let person: Person?

    public init(kind: Kind, identifier: String? = nil, person: Person? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.person = person
    }
}

/// Where a change feed was read up to.
///
/// Opaque bytes from the framework. Keep it, hand it back next time, and only
/// what happened since comes back.
public struct ChangeToken: Sendable, Equatable, Codable {

    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}
