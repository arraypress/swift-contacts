//
//  Person+ItemProvider.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Dragging a contact out, and catching one dropped in.
//
//  `CNContact` conforms to `NSItemProviderReading` and `NSItemProviderWriting`,
//  which is what makes a contact draggable between apps, pasteable, and
//  shareable. The conformance lives on the framework's reference type, so a
//  library built on a value type has to bridge it — that is all this is.
//
//  No UIKit or AppKit here: `NSItemProvider` is Foundation, so this compiles
//  everywhere the rest of the library does, including a command-line tool that
//  will never use it.
//

import Contacts
import Foundation

public extension Person {

    /// This contact, ready to be dragged, copied or shared.
    ///
    /// The receiving app gets a real `CNContact` — the system registers the
    /// vCard type alongside it — so it lands in Contacts.app, Mail or anything
    /// else that accepts one, without this library agreeing a format with them.
    var itemProvider: NSItemProvider {
        NSItemProvider(object: ContactBridge.mutable(from: self))
    }

    /// Reads a contact out of something dropped or pasted.
    ///
    /// - Returns: The contact, or `nil` when the provider was carrying
    ///   something else. A drop is an unpredictable thing to be handed, so
    ///   "this was not a contact" is an ordinary answer rather than an error.
    static func from(_ provider: NSItemProvider) async throws -> Person? {
        guard provider.canLoadObject(ofClass: CNContact.self) else { return nil }

        // Converted to the value type INSIDE the handler. `CNContact` is not
        // `Sendable`, so resuming the continuation with one does not compile
        // under Swift 6 — and the reason it does not is real: the handler runs
        // on an arbitrary queue and the object would cross to another.
        // `Person` is a value and crosses safely.
        return try await withCheckedThrowingContinuation { continuation in
            // The handler is called exactly once.
            _ = provider.loadObject(ofClass: CNContact.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let contact = object as? CNContact {
                    continuation.resume(returning: ContactBridge.person(from: contact))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Reads every contact out of a drop carrying several.
    ///
    /// Providers that hold something else are skipped rather than failing the
    /// lot: a drag of three contacts and a photograph should yield three
    /// contacts.
    static func from(_ providers: [NSItemProvider]) async -> [Person] {
        var people: [Person] = []
        for provider in providers {
            if let person = try? await from(provider) { people.append(person) }
        }
        return people
    }
}

public extension Collection where Element == Person {

    /// These contacts, ready to be dragged as a group.
    var itemProviders: [NSItemProvider] { map(\.itemProvider) }
}
