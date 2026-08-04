// swift-tools-version: 5.9
//
//  rnp-cli — standalone SwiftPM package for the `rnp` macOS CLI.
//  Lives in its own subdirectory so it doesn't collide with the
//  Xcode project (`MailApp/RnpMail.xcodeproj`) at the repo root.
//
//  Build:   `cd rnp-cli && swift build -c release`
//  Run:     `.build/release/rnp --help`
//  Install: `cp .build/release/rnp /usr/local/bin/rnp`
//

import PackageDescription

let package = Package(
    name: "rnp-cli",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "rnp", targets: ["rnp-cli"]),
    ],
    dependencies: [
        // swift-rnp exposes MailSecurityEngine, Rnp, KeyringStore.
        // The CLI shares the same engine as the GUI app — one source
        // of truth for OpenPGP behavior.
        .package(url: "https://github.com/rnpgp/swift-rnp.git", from: "0.2.10"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "rnp-cli",
            dependencies: [
                .product(name: "MailSecurityEngine", package: "swift-rnp"),
                .product(name: "Rnp", package: "swift-rnp"),
                .product(name: "KeyringStore", package: "swift-rnp"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/rnp-cli"
        ),
    ]
)
