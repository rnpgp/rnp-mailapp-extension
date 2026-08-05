//
//  SyncConfiguration.swift
//  RNP
//
//  Observable model for the Sync UI. Tracks the user's choices for
//  canonical store, active import sources, passphrase store. Persists
//  to UserDefaults so choices survive relaunches.
//
//  See TODO.complete/32-sync-settings-ui.md.
//

import Combine
import Foundation

public final class SyncConfiguration: ObservableObject {

    /// Identifier of the chosen canonical store. Persisted.
    @Published public var canonicalStoreID: String {
        didSet { UserDefaults.standard.set(canonicalStoreID, forKey: Self.canonicalKey) }
    }

    /// Path for per-key dir backend, when canonicalStoreID is "rnp-asc-dir".
    @Published public var perKeyDirectoryPath: String {
        didSet { UserDefaults.standard.set(perKeyDirectoryPath, forKey: Self.ascDirKey) }
    }

    /// Set of enabled import-source identifiers. Persisted.
    @Published public var enabledImportSources: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledImportSources), forKey: Self.sourcesKey) }
    }

    /// Identifier of the chosen passphrase store. Persisted.
    @Published public var passphraseStoreID: String {
        didSet { UserDefaults.standard.set(passphraseStoreID, forKey: Self.passphraseKey) }
    }

    public init() {
        self.canonicalStoreID = UserDefaults.standard.string(forKey: Self.canonicalKey) ?? "rnp-local"
        self.perKeyDirectoryPath = UserDefaults.standard.string(forKey: Self.ascDirKey) ?? ""
        self.enabledImportSources = Set(UserDefaults.standard.stringArray(forKey: Self.sourcesKey)
                                        ?? ["gnupg", "paste", "file"])
        self.passphraseStoreID = UserDefaults.standard.string(forKey: Self.passphraseKey) ?? "keychain"
    }

    private static let canonicalKey = "sync.canonicalStore"
    private static let ascDirKey = "sync.perKeyDirPath"
    private static let sourcesKey = "sync.importSources"
    private static let passphraseKey = "sync.passphraseStore"

    // MARK: Available options (declared once; UI binds to these)

    public static let canonicalOptions: [CanonicalOption] = [
        CanonicalOption(id: "rnp-local", title: "Local RNP keyring",
                        description: "~/Library/Group Containers/.../keyring — fastest, stays on this Mac"),
        CanonicalOption(id: "rnp-asc-dir", title: "Per-key .asc directory",
                        description: "One .asc file per key. Sync via iCloud Drive, Dropbox, Syncthing, git. Best for Mac+Linux."),
        CanonicalOption(id: "rnp-cloudkit", title: "iCloud (CloudKit)",
                        description: "Automatic sync to your iPhone. Requires iCloud sign-in.")
    ]

    public static let importSourceOptions: [ImportSourceOption] = [
        ImportSourceOption(id: "gnupg", title: "GnuPG keyring",
                           description: "Read ~/.gnupg read-only. RNP never modifies it."),
        ImportSourceOption(id: "wkd", title: "WKD (Web Key Directory)",
                           description: "Fetch recipient keys by email from openpgpkey.<domain>."),
        ImportSourceOption(id: "keys.openpgp.org", title: "keys.openpgp.org",
                           description: "Search the public Verifpserver by email or fingerprint."),
        ImportSourceOption(id: "paste", title: "Paste from clipboard",
                           description: "Detect PGP blocks on the clipboard."),
        ImportSourceOption(id: "file", title: "Drag-drop files",
                           description: ".asc / .gpg / .pgp files dropped into the window.")
    ]

    public static let passphraseStoreOptions: [PassphraseOption] = [
        PassphraseOption(id: "keychain", title: "macOS Keychain",
                         description: "Per-device. Never leaves this Mac."),
        PassphraseOption(id: "icloud-keychain", title: "iCloud Keychain",
                         description: "Syncs to your iPhone. End-to-end encrypted by Apple."),
        PassphraseOption(id: "prompt", title: "Prompt every time",
                         description: "No storage. Type the passphrase each operation.")
    ]
}

public struct CanonicalOption: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
}

public struct ImportSourceOption: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
}

public struct PassphraseOption: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
}
