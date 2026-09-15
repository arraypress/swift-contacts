//
//  VCardPhotos.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Putting the photographs back into the vCard.
//
//  `CNContactVCardSerialization` does not write them. Measured, not inferred:
//  an address book where 26 of 68 contacts carry image data serialises to a
//  vCard containing **zero** PHOTO properties, and fetching the image key
//  explicitly changes nothing — the output is byte-identical. Contacts.app's
//  own export does include them, by some route that is not this API.
//
//  That matters more than it sounds. A vCard is the format you reach for when
//  you want a backup that any system can read, and one that quietly leaves the
//  faces behind is not a backup — you find out when you restore.
//
//  So the photographs are spliced in afterwards, as vCard 3.0 requires:
//  base64, folded to 75 octets, continuation lines beginning with a space.
//

import Foundation

/// Adds PHOTO properties to a vCard that Apple wrote without them.
enum VCardPhotos {

    /// Where a card ends. Apple writes CRLF throughout, and so must we.
    private static let terminator = "END:VCARD"
    private static let newline = "\r\n"

    /// Splices one photograph into each card that has one.
    ///
    /// - Parameters:
    ///   - data: A vCard document from `CNContactVCardSerialization`.
    ///   - photos: One entry per card, in the same order, `nil` where there is
    ///     no picture.
    /// - Returns: The document with photographs added — or unchanged, if the
    ///   card count does not match. **A mismatch is never guessed past**: the
    ///   failure mode of getting it wrong is somebody's face attached to
    ///   somebody else's name, which is far worse than a missing photograph.
    static func splice(into data: Data, photos: [Data?]) -> Data {
        guard photos.contains(where: { $0 != nil }),
              let text = String(data: data, encoding: .utf8)
        else { return data }

        let cards = text.components(separatedBy: terminator)
        // Trailing text after the final END:VCARD leaves one extra component.
        guard cards.count - 1 == photos.count else { return data }

        var out = ""
        out.reserveCapacity(text.count + photos.compactMap { $0?.count }.reduce(0, +) * 2)

        for (index, card) in cards.enumerated() {
            out += card
            guard index < photos.count else { continue }
            if let photo = photos[index], let property = property(for: photo) {
                out += property
            }
            out += terminator
        }
        return Data(out.utf8)
    }

    /// One folded PHOTO property, ready to sit before `END:VCARD`.
    static func property(for photo: Data) -> String? {
        guard !photo.isEmpty else { return nil }
        let encoded = photo.base64EncodedString()
        let header = "PHOTO;ENCODING=b;TYPE=\(imageType(of: photo)):"
        return fold(header + encoded) + newline
    }

    /// Folds a long line the way vCard demands: 75 octets, then CRLF and a
    /// single space to continue.
    ///
    /// A reader that meets an unfolded 40 KB line is entitled to reject the
    /// card, and several do.
    static func fold(_ line: String, at width: Int = 75) -> String {
        guard line.count > width else { return line }
        var out = ""
        var index = line.startIndex
        var first = true

        while index < line.endIndex {
            // The continuation space counts towards the limit.
            let take = first ? width : width - 1
            let end = line.index(index, offsetBy: take, limitedBy: line.endIndex) ?? line.endIndex
            if !first { out += newline + " " }
            out += line[index..<end]
            index = end
            first = false
        }
        return out
    }

    /// The `TYPE` parameter, read from the bytes rather than assumed.
    static func imageType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "JPEG" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "PNG" }
        // Contacts stores JPEG in practice; saying so is better than omitting
        // the parameter, which some readers treat as a hard error.
        return "JPEG"
    }
}
