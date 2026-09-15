# Swift Contacts

The address book as values you can hold: read it, search it, change it, export
it — and put back anything a change got wrong.

```swift
import ContactsKit

let store = ContactStore()
try await store.requestAccess()

for person in try store.all() {
    person.displayName          // "Ada Lovelace", ordered the way the system orders it
    person.primaryPhone         // "+44 7700 900123"
    person.emailAddresses       // labelled: work, home, iCloud, or whatever they typed
}
```

Everything is a `Sendable`, `Codable` value type. `CNContact` appears at exactly
two edges — where the store is actually touched — and nowhere else.

## Why a value type

`CNContact` is a reference type, is not `Sendable`, is not `Codable`, and
**traps when asked for a property that was not fetched**. Not returns nil —
raises, uncatchably, killing the process. None of that is wrong for a framework
talking to a store, and all of it is wrong for something you want to hand
between tasks, write to JSON, diff for a dry run, or build from a CSV row
before any store exists.

So every read here is guarded by `isKeyAvailable`, and a field you did not ask
for comes back empty rather than fatal.

## Changing things, and changing them back

```swift
let journal = UndoJournal(directory: .applicationSupportDirectory.appending(path: "undo"))

var ada = try store.search(name: "Ada").first!
ada.jobTitle = "Countess of Lovelace"
try store.update(ada, journal: journal, reason: "correcting the title")

// Regretted it
try store.undo(journal.latest()!, journal: journal)
```

**Every write records its reversal before it happens.** If the journal cannot be
written, the write does not happen — an unrecorded change is exactly the one
you would want back. This exists because the point of the library is editing by
*describing* the edit, which means something other than a person is choosing
which records change.

Undoing a deletion restores the contact with a **new identifier**. The store
will not let a caller choose one, so anything holding the old id will not find
it again.

## Export and import

```swift
let archive = ContactArchive(store: store)
try archive.export(format: .vcard, to: url)     // a real backup
try archive.export(format: .csv, to: url)       // something to read

let people = try archive.read(contentsOf: url)  // reads, writes nothing
try archive.restore(people, journal: journal)   // this is the part that writes
```

Reading a file and putting its contents in someone's address book are separate
calls on purpose. Import **adds**, never merges: deciding an incoming record is
the same person as an existing one is a judgement, and making it silently
during a restore is how duplicates and overwrites happen.

CSV says it is lossy — `ContactFormat.isLossless` — because several phone
numbers collapse into one cell and a photograph becomes the word `(photo)`.
vCard is the one to back up with.

## What the SDK does that this does too

All 30 contact fields · groups, containers and membership · all twelve
predicates · vCard · **change history**, through a small Objective-C shim,
because `enumeratorForChangeHistoryFetchRequest:` is marked
`NS_SWIFT_UNAVAILABLE` with no Swift replacement · drag and drop via
`NSItemProvider` · locale-aware name and address formatting.

Not covered: `CNContactProperty`, because nothing outside a `CNContactPicker`
ever produces one.

## Things that cost an afternoon

Each was measured on a real address book, and each is now a test.

**A note without the entitlement fails the entire save.** Not the note — the
save. `NSCocoaErrorDomain` 134092, whose message is "The operation couldn't be
completed." So `note` is opt-in (`writeNote:`), and that error maps to one that
says what to do. Found by adding fields one at a time until the store refused.

**vCard serialisation silently drops every photograph.** An address book where
26 of 68 contacts have images serialises to a vCard with **zero** PHOTO
properties, and asking for the image key explicitly changes nothing — the
output is byte-identical. Contacts.app's own export includes them, by some
route that is not this API. So they are spliced in afterwards as vCard 3.0
requires: base64, folded at 75 octets. If the card count and photo count ever
disagree, **no** photos are written rather than risking one person's face on
another person's card.

**An update rewrites the whole record.** `CNSaveRequest` writes every field, so
building a fresh `CNMutableContact` to change a job title blanks the phone
numbers. Updates here re-fetch and edit in place — asserted by a test that
changes one field and checks the others survive.

**Phone matching is less forgiving than it looks.** Measured: the number as
stored matches, spaces removed matches, **digits only does not**, and a
trailing fragment does not. Dropping a `+` changes the number as far as the
store is concerned. There is a Swift-side fallback for the looser case, tried
only when the store's own predicate finds nothing.

**Labels arrive three ways.** `_$!<Mobile>!$_` is the framework's spelling and
its delimiters cannot be trimmed — a contact saved with plain `Mobile` loses
its localisation and its icon. A real address book also held a **blank** label,
and an `iPhone` label stored as plain text rather than the constant, because it
came from Google. So: read leniently, match case-insensitively, write the
constant where one exists, pass anything custom through.

**`\r\n` is one Swift `Character`.** Comparing a `Character` to `"\r"` matches
nothing in a CRLF document, which is every RFC 4180 CSV. The first version of
the reader merged every row into one. It scans unicode scalars now.

**The service lists are ancient.** Social offers MySpace and Yelp; instant
messaging offers AIM, ICQ and MSN. No Mastodon, Bluesky, Signal or WhatsApp.
But `service` is a plain `String`, and custom ones store and read back
perfectly — verified with Mastodon, Bluesky and Signal.

**Photographs go opaque after an iCloud round trip.** A 20 KB image written to
a CardDAV container reads back at full size immediately and from another
process seconds later — and returns **zero bytes** twenty seconds after that,
while Contacts.app still displays it. Photos that were synced *down* read
fine. Worth knowing before trusting a photo count.

**Some of Contacts.app is not in Contacts.** Pronouns, ringtone, text tone and
contact posters appear in the app and exist nowhere in the framework headers.
No third-party app can read or write them.

## Command-line tools need an Info.plist

A bare executable has no bundle, so it has no `NSContactsUsageDescription`, so
requesting access **crashes it** rather than prompting. Embed one:

```sh
swiftc … -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
```

Permission also follows the binary's code signature, so a rebuilt tool is a new
tool as far as the system is concerned, and asks again.

## Editing while Contacts.app is open

Don't. Its edit sheet rewrites the whole record from whatever its form is
carrying, which will undo what a tool just wrote. Nothing here can prevent it.

## Requirements

macOS 14+ / iOS 17+ / visionOS 1+ / watchOS 10+, Swift 6. No external
dependencies; the one internal target is the Objective-C shim.

Reading notes needs `com.apple.developer.contacts.notes`, which Apple grants by
request. Nested groups are macOS-only; `CNAuthorizationStatusLimited` is
iOS-only.

## Licence

MIT.
