//
//  ContactGroup.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//

import Contacts
import Foundation

/// A named set of contacts.
///
/// Groups belong to a container — an account — and a contact can be in
/// several. They are the thing Contacts.app shows in its sidebar, and the
/// thing a mail client means by a distribution list.
public struct ContactGroup: Sendable, Equatable, Codable, Identifiable {

    /// The store's identifier for the group.
    public let id: String

    /// What it is called.
    public var name: String

    public init(id: String = "", name: String = "") {
        self.id = id
        self.name = name
    }

    init(_ group: CNGroup) {
        self.init(id: group.identifier, name: group.name)
    }
}

/// An account contacts live in: iCloud, an Exchange server, On My Mac.
///
/// Read-only. A container is created by adding an account in System Settings,
/// never by an app, so there is nothing here to write.
public struct ContactContainer: Sendable, Equatable, Codable, Identifiable {

    /// What sort of account it is.
    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        case local
        case exchange
        case cardDAV
        case unassigned

        init(_ type: CNContainerType) {
            switch type {
            case .local: self = .local
            case .exchange: self = .exchange
            case .cardDAV: self = .cardDAV
            case .unassigned: self = .unassigned
            @unknown default: self = .unassigned
            }
        }
    }

    public let id: String
    public var name: String
    public var kind: Kind

    public init(id: String = "", name: String = "", kind: Kind = .unassigned) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    init(_ container: CNContainer) {
        self.init(id: container.identifier, name: container.name, kind: Kind(container.type))
    }
}
