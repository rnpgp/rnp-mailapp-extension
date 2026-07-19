//
//  KeyManager.swift
//  swift-rnp
//
//  Persistent OpenPGP key management for the mail security engine.
//
//  A KeyManager owns an `Rnp` context whose in-memory keyrings are loaded
//  from (and persisted to) a keyring directory holding classic GPG keyring
//  files (pubring.gpg / secring.gpg). Passphrases are supplied by the
//  caller-provided `Rnp.PassphraseProvider`, so secret storage (Keychain on
//  Apple platforms) stays outside of this package.
//

import Foundation
import Rnp

/// Key generation algorithms supported by `KeyManager.generateKey`.
public enum KeyAlgorithm: String, CaseIterable {
    /// RSA-3072 signing primary with an RSA-3072 encryption subkey.
    case rsa = "RSA"
    /// ECDSA P-256 signing primary with an ECDH P-256 encryption subkey.
    case ecdsa = "ECDSA"
}

/// A snapshot description of one primary key in the keyring.
public struct KeyInfo: Equatable, Identifiable {
    public let fingerprint: String
    public let primaryUserID: String
    public let userIDs: [String]
    public let hasSecret: Bool
    public let algorithm: String
    public let bits: Int
    public let creationDate: Date
    public let expirationDate: Date?
    public let isRevoked: Bool
    public let subkeyCount: Int

    public init(
        fingerprint: String,
        primaryUserID: String,
        userIDs: [String],
        hasSecret: Bool,
        algorithm: String = "",
        bits: Int = 0,
        creationDate: Date = Date(timeIntervalSince1970: 0),
        expirationDate: Date? = nil,
        isRevoked: Bool = false,
        subkeyCount: Int = 0
    ) {
        self.fingerprint = fingerprint
        self.primaryUserID = primaryUserID
        self.userIDs = userIDs
        self.hasSecret = hasSecret
        self.algorithm = algorithm
        self.bits = bits
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.isRevoked = isRevoked
        self.subkeyCount = subkeyCount
    }

    public var id: String { fingerprint }

    /// Short, user-facing label like "RSA-3072" or "ECDSA P-256".
    public var algorithmLabel: String {
        algorithm.isEmpty ? "OpenPGP" : bits > 0 ? "\(algorithm)-\(bits)" : algorithm
    }

    /// Whether the key has expired.
    public var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return expiration < Date()
    }

    /// Days until expiry; `nil` for non-expiring keys.
    public var daysUntilExpiry: Int? {
        guard let expiration = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
    }
}

/// Errors thrown by `KeyManager`.
public enum KeyManagerError: Error, Equatable {
    /// A keyring file exists but could not be read.
    case keyringUnreadable(String)
}

/// Manages an OpenPGP keyring directory for the mail extension and its
/// container app.
///
/// All operations run serialized on an internal lock; instances are safe to
/// share between MailKit callback threads and UI code.
public final class KeyManager {
    /// File name of the public keyring inside the keyring directory.
    public static let publicKeyringFilename = "pubring.gpg"
    /// File name of the secret keyring inside the keyring directory.
    public static let secretKeyringFilename = "secring.gpg"

    /// Directory holding the keyring files.
    public let directory: URL

    private let lock = NSRecursiveLock()
    private let rnp: Rnp

    /// Creates a manager, creating the directory and loading any existing
    /// keyring files.
    public init(directory: URL, passphraseProvider: @escaping Rnp.PassphraseProvider) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        rnp = try Rnp(passphraseProvider: passphraseProvider)
        try loadKeyring(publicKeyringURL, public: true, secret: false)
        try loadKeyring(secretKeyringURL, public: false, secret: true)
    }

    /// Convenience manager answering every passphrase request with `password`.
    public convenience init(directory: URL, password: String) throws {
        try self.init(directory: directory, passphraseProvider: { _ in password })
    }

    private var publicKeyringURL: URL {
        directory.appendingPathComponent(Self.publicKeyringFilename)
    }

    private var secretKeyringURL: URL {
        directory.appendingPathComponent(Self.secretKeyringFilename)
    }

    private func loadKeyring(_ url: URL, public: Bool, secret: Bool) throws {
        guard let data = FileManager.default.contents(atPath: url.path), !data.isEmpty else {
            return
        }
        do {
            try rnp.loadKeys(data, public: `public`, secret: secret)
        } catch {
            throw KeyManagerError.keyringUnreadable(url.lastPathComponent)
        }
    }

    /// Runs `body` with the managed `Rnp` context under the manager lock.
    ///
    /// Used by `MailSecurityEngine` to perform crypto operations on the
    /// shared keyrings without racing other callers.
    func withRnp<T>(_ body: (Rnp) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(rnp)
    }

    // MARK: - Listing

    /// All primary keys in the keyring, in enumeration order.
    public func listKeys() throws -> [KeyInfo] {
        try withRnp { rnp in
            var order: [String] = []
            var infos: [String: KeyInfo] = [:]
            for userID in try rnp.allUserIDs() {
                guard let key = try rnp.locateKey(userID) else {
                    continue
                }
                let fingerprint = try key.fingerprint
                if let existing = infos[fingerprint] {
                    infos[fingerprint] = KeyInfo(
                        fingerprint: existing.fingerprint,
                        primaryUserID: existing.primaryUserID,
                        userIDs: existing.userIDs + [userID],
                        hasSecret: existing.hasSecret,
                        algorithm: existing.algorithm,
                        bits: existing.bits,
                        creationDate: existing.creationDate,
                        expirationDate: existing.expirationDate,
                        isRevoked: existing.isRevoked,
                        subkeyCount: existing.subkeyCount
                    )
                } else {
                    order.append(fingerprint)
                    infos[fingerprint] = try makeKeyInfo(key: key, primaryUserID: userID)
                }
            }
            return order.compactMap { infos[$0] }
        }
    }

    private func makeKeyInfo(key: RnpKey, primaryUserID: String) throws -> KeyInfo {
        let fingerprint = try key.fingerprint
        let expirationSeconds = try key.expirationSeconds
        let expirationDate: Date? = expirationSeconds > 0
            ? try key.creationDate.addingTimeInterval(TimeInterval(expirationSeconds))
            : nil
        return KeyInfo(
            fingerprint: fingerprint,
            primaryUserID: (try? key.primaryUserID) ?? primaryUserID,
            userIDs: (try? key.userIDs) ?? [],
            hasSecret: (try? key.hasSecret) ?? false,
            algorithm: (try? key.algorithm) ?? "",
            bits: (try? key.bits) ?? 0,
            creationDate: (try? key.creationDate) ?? Date(timeIntervalSince1970: 0),
            expirationDate: expirationDate,
            isRevoked: (try? key.isRevoked) ?? false,
            subkeyCount: (try? key.subkeys.count) ?? 0
        )
    }

    // MARK: - Generation

    /// Generates a new key pair and persists the keyrings.
    @discardableResult
    public func generateKey(userID: String, algorithm: KeyAlgorithm = .rsa) throws -> KeyInfo {
        try withRnp { rnp in
            let json = algorithm == .rsa
                ? Rnp.rsaKeyGenJSON(userid: userID)
                : Rnp.ecdsaP256KeyGenJSON(userid: userID)
            try rnp.generateKey(json: json)
            let key = try rnp.requireKey(userID)
            let info = try makeKeyInfo(key: key, primaryUserID: userID)
            try persist(rnp)
            return info
        }
    }

    // MARK: - Import / export

    /// Imports keys (armored or binary) and persists the keyrings.
    ///
    /// - Returns: snapshots of the imported primary keys.
    @discardableResult
    public func importKeys(_ data: Data) throws -> [KeyInfo] {
        try withRnp { rnp in
            let results = try rnp.importKeys(data)
            try persist(rnp)
            // The results JSON lists every imported key packet, including
            // subkeys; keep primary keys (those carrying user IDs) only.
            return Self.importedFingerprints(fromJSON: results).compactMap { fingerprint in
                guard let key = try? rnp.locateKey(fingerprint, type: .fingerprint),
                      let userIDs = try? key.userIDs, !userIDs.isEmpty
                else {
                    return nil
                }
                return try? makeKeyInfo(key: key, primaryUserID: userIDs[0])
            }
        }
    }

    /// Exports a key by fingerprint (armored by default).
    public func exportKey(fingerprint: String, secret: Bool = false, armored: Bool = true) throws -> Data {
        try withRnp { rnp in
            try rnp.requireKey(fingerprint, type: .fingerprint)
                .exportKey(secret: secret, armored: armored)
        }
    }

    /// Fingerprints found in an `rnp_import_keys` results JSON document.
    static func importedFingerprints(fromJSON json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = object["keys"] as? [[String: Any]]
        else {
            return []
        }
        return keys.compactMap { $0["fingerprint"] as? String }
    }

    // MARK: - Deletion

    /// Removes a key (public, secret and subkeys) and persists the keyrings.
    public func deleteKey(fingerprint: String) throws {
        try withRnp { rnp in
            let key = try rnp.requireKey(fingerprint, type: .fingerprint)
            try rnp.remove(key: key)
            try persist(rnp)
        }
    }

    // MARK: - Key resolution

    /// Finds a public key for a recipient identifier.
    ///
    /// The identifier may be a full user ID ("Alice <alice@example.com>") or
    /// a bare email address; email matching against the `<...>` part of
    /// stored user IDs is case-insensitive.
    public func publicKey(for identifier: String) throws -> RnpKey? {
        try withRnp { try publicKeyUnlocked(for: identifier, rnp: $0) }
    }

    /// Finds a key with secret material for a sender identifier (see
    /// `publicKey(for:)` for the matching rules).
    public func secretKey(forUserID identifier: String) throws -> RnpKey? {
        try withRnp { rnp in
            guard let key = try publicKeyUnlocked(for: identifier, rnp: rnp),
                  try key.hasSecret
            else {
                return nil
            }
            return key
        }
    }

    /// Lock-free variant of `publicKey(for:)` for callers already holding
    /// the manager lock.
    func publicKeyUnlocked(for identifier: String, rnp: Rnp) throws -> RnpKey? {
        if let key = try rnp.locateKey(identifier) {
            return key
        }
        let email = Self.emailAddress(from: identifier) ?? identifier
        for userID in try rnp.allUserIDs() {
            let matches = userID.caseInsensitiveCompare(identifier) == .orderedSame
                || Self.emailAddress(from: userID)?.caseInsensitiveCompare(email) == .orderedSame
            if matches {
                return try rnp.locateKey(userID)
            }
        }
        return nil
    }

    /// Lock-free variant of `secretKey(forUserID:)` for callers already
    /// holding the manager lock.
    func secretKeyUnlocked(forUserID identifier: String, rnp: Rnp) throws -> RnpKey? {
        guard let key = try publicKeyUnlocked(for: identifier, rnp: rnp),
              try key.hasSecret
        else {
            return nil
        }
        return key
    }

    /// Extracts the email address from a user ID of the form
    /// "Name <email@example.com>", or returns the input itself when it looks
    /// like a bare email address.
    static func emailAddress(from userID: String) -> String? {
        if let open = userID.lastIndex(of: "<"),
           let close = userID.lastIndex(of: ">"), open < close
        {
            return String(userID[userID.index(after: open) ..< close])
        }
        return userID.contains("@") ? userID : nil
    }

    // MARK: - Persistence

    /// Writes the in-memory keyrings back to the keyring directory.
    ///
    /// Keyrings that hold no keys are removed instead of written, so a
    /// freshly initialized or fully emptied manager leaves no files that a
    /// later load would choke on.
    private func persist(_ rnp: Rnp) throws {
        let publicKeys = try rnp.publicKeyCount > 0 ? rnp.savePublicKeys(armored: false) : nil
        let secretKeys = try rnp.secretKeyCount > 0 ? rnp.saveSecretKeys(armored: false) : nil
        try persistKeyring(publicKeys, to: publicKeyringURL)
        try persistKeyring(secretKeys, to: secretKeyringURL)
    }

    private func persistKeyring(_ data: Data?, to url: URL) throws {
        if let data {
            try data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
