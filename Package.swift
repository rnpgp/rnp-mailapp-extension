// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-rnp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "Rnp", targets: ["Rnp"]),
        .library(name: "MailSecurityEngine", targets: ["MailSecurityEngine"]),
        .library(name: "KeyLifecycle", targets: ["KeyLifecycle"]),
        .library(name: "KeyServerClient", targets: ["KeyServerClient"]),
        .library(name: "RnpMailUI", targets: ["RnpMailUI"]),
        .library(name: "TrustStore", targets: ["TrustStore"])
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
            name: "TrustStore",
            dependencies: []
        ),
        .target(
            name: "MailSecurityEngine",
            dependencies: ["Rnp", "KeyServerClient", "TrustStore"]
        ),
        .target(
            name: "KeyLifecycle",
            dependencies: ["Rnp", "MailSecurityEngine"]
        ),
        .target(
            name: "RnpMailUI",
            dependencies: ["MailSecurityEngine", "KeyLifecycle", "TrustStore"]
        ),
        .target(
            name: "KeyServerClient",
            dependencies: []
        ),
        .testTarget(
            name: "RnpTests",
            dependencies: ["Rnp"]
        ),
        .testTarget(
            name: "MailSecurityEngineTests",
            dependencies: ["MailSecurityEngine"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "KeyLifecycleTests",
            dependencies: ["KeyLifecycle"]
        ),
        .testTarget(
            name: "RnpMailUITests",
            dependencies: ["RnpMailUI"]
        ),
        .testTarget(
            name: "KeyServerClientTests",
            dependencies: ["KeyServerClient"]
        ),
        .testTarget(
            name: "TrustStoreTests",
            dependencies: ["TrustStore"]
        )
    ]
)
