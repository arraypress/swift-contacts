// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-contacts",
    platforms: [
        .macOS(.v14), .iOS(.v17), .visionOS(.v1), .watchOS(.v10)
    ],
    products: [
        .library(name: "ContactsKit", targets: ["ContactsKit"]),
    ],
    targets: [
        // No external dependencies. The Contacts framework is the whole job,
        // and a library that reads someone's address book should be readable
        // in one sitting by the person deciding whether to trust it.
        //
        // The one internal target is an Objective-C shim for the two APIs the
        // SDK marks NS_SWIFT_UNAVAILABLE — see CContactsBridge.h.
        .target(name: "CContactsBridge"),
        .target(name: "ContactsKit", dependencies: ["CContactsBridge"]),
        .testTarget(name: "ContactsKitTests", dependencies: ["ContactsKit"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
