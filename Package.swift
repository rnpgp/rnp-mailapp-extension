// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-rnp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "Rnp", targets: ["Rnp"]),
        .library(name: "MailSecurityEngine", targets: ["MailSecurityEngine"])
    ],
    targets: [
        .systemLibrary(
            name: "CRnp",
            path: "Sources/CRnp",
            pkgConfig: "librnp",
            providers: [
                .brew(["rnp"]),
                .apt(["librnp-dev"])
            ]
        ),
        .target(
            name: "Rnp",
            dependencies: ["CRnp"]
        ),
        .target(
            name: "MailSecurityEngine",
            dependencies: ["Rnp"]
        ),
        .testTarget(
            name: "RnpTests",
            dependencies: ["Rnp"]
        ),
        .testTarget(
            name: "MailSecurityEngineTests",
            dependencies: ["MailSecurityEngine"]
        )
    ]
)
