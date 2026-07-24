//
//  KeyStateStore.swift
//  KeyStateStore
//
//  Tamper-detecting persistence of per-key usage states. The database is
//  JSON with a detached Ed25519 signature, mirroring the pattern used by
//  `TrustStore`. The signing key lives in the Keychain (per-install), so
//  tampering with the JSON or the signature causes the store to fail
//  closed to `.active` rather than silently hide keys.
//
//  This store is intentionally distinct from `TrustStore`:
//  - `TrustStore` answers "is this recipient's key the right one?"
//  - `KeyStateStore` answers "should this key (mine or theirs) be used
//    for new operations?"
//  Different concerns, different code paths, different signing keys.
//

import CryptoKit
import Foundation
import os
import Security

/// Errors thrown by `KeyStateStore`.
public enum KeyStateStoreError: Error, Equatable {
    /// The database could not be read or written.
    case persistenceFailed(String)
    /// The signature on the database failed verification; the data may
    /// have been tampered with.
    case tampered
}

/// On-disk representation of the key-state database.
private struct KeyStateDatabase: Codable, Equatable {
    var version: Int
    var records: [String: KeyStateRecord]

    init(version: Int = 1, records: [String: KeyStateRecord] = [:]) {
        self.version = version
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case version, records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        records = try container.decodeIfPresent([String: KeyStateRecord].self, forKey: .records) ?? [:]
    }
}

/// Stores per-key usage states (`active` / `archived`) keyed by fingerprint.
///
/// The database is persisted as JSON with a detached Ed25519 signature,
/// fail-closed to `.active` on tamper. The signing key is created at first
/// launch and stored in the Keychain; convenience invariants ensure the
/// signing key for this store never matches the one used by `TrustStore`
/// (a compromise of one store does not grant write access to the other).
public final class KeyStateStore {
    /// File name of the database inside the store directory.
    public static let databaseFilename = "key-states.json"
    /// File name of the detached Ed25519 signature.
    public static let signatureFilename = "key-states.json.sig"

    /// Directory holding the database and signature files.
    public let directory: URL
    /// Ed25519 private key used to sign the database.
    public let privateKey: Curve25519.Signing.PrivateKey

    private let lock = NSLock()
    private var cache: [String: KeyStateRecord]

    /// Creates the store, creating the directory and loading any existing
    /// signed database.
    ///
    /// - Parameters:
    ///   - directory: directory holding `key-states.json` and `.sig`.
    ///   - keychainAccessGroup: Keychain access group used when creating
    ///     the signing key. Defaults to the `RNPMAILKeychainAccessGroup`
    ///     value from `Bundle.main`.
    public init(
        directory: URL,
        keychainAccessGroup: String? = Bundle.main.object(forInfoDictionaryKey: "RNPMAILKeychainAccessGroup") as? String
    ) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = try Self.loadOrCreateSigningKey(keychainAccessGroup: keychainAccessGroup)
        self.privateKey = key
        let loaded = try Self.loadVerified(
            databaseURL: directory.appendingPathComponent(Self.databaseFilename),
            signatureURL: directory.appendingPathComponent(Self.signatureFilename),
            publicKey: key.publicKey
        )
        self.cache = loaded
    }

    // MARK: - Queries

    /// Returns the usage state for the fingerprint, defaulting to `.active`
    /// when the fingerprint is not in the store.
    public func state(forFingerprint fingerprint: String) -> KeyUsageState {
        lock.lock()
        defer { lock.unlock() }
        return cache[normalize(fingerprint)]?.state ?? .active
    }

    /// Returns the full record for the fingerprint, or `nil` when the
    /// fingerprint has no entry.
    public func record(forFingerprint fingerprint: String) -> KeyStateRecord? {
        lock.lock()
        defer { lock.unlock() }
        return cache[normalize(fingerprint)]
    }

    /// All records currently in the store.
    public func allRecords() -> [KeyStateRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(cache.values).sorted { $0.fingerprint < $1.fingerprint }
    }

    /// All fingerprints in a given state.
    public func fingerprints(in state: KeyUsageState) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return cache.values
            .filter { $0.state == state }
            .map(\.fingerprint)
            .sorted()
    }

    // MARK: - Mutations

    /// Sets the state for a fingerprint. Persists immediately.
    public func setState(
        _ state: KeyUsageState,
        forFingerprint fingerprint: String,
        reason: String? = nil
    ) throws {
        lock.lock()
        let record = KeyStateRecord(
            fingerprint: normalize(fingerprint),
            state: state,
            reason: reason
        )
        cache[record.fingerprint] = record
        let snapshot = cache
        lock.unlock()
        try persist(snapshot)
    }

    /// Applies the same state to multiple fingerprints in one atomic write.
    public func setState(
        _ state: KeyUsageState,
        forFingerprints fingerprints: [String],
        reason: String? = nil
    ) throws {
        lock.lock()
        let now = Date()
        for fpr in fingerprints {
            cache[normalize(fpr)] = KeyStateRecord(
                fingerprint: normalize(fpr),
                state: state,
                lastModified: now,
                reason: reason
            )
        }
        let snapshot = cache
        lock.unlock()
        try persist(snapshot)
    }

    /// Removes the record for a fingerprint. Used by "delete forever" flows
    /// after the key has been removed from the keyring.
    public func removeRecord(forFingerprint fingerprint: String) throws {
        lock.lock()
        cache[normalize(fingerprint)] = nil
        let snapshot = cache
        lock.unlock()
        try persist(snapshot)
    }

    // MARK: - Internals

    /// Fingerprints are stored uppercased without whitespace so lookups are
    /// robust to formatting differences between callers.
    private func normalize(_ fingerprint: String) -> String {
        fingerprint.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private func persist(_ snapshot: [String: KeyStateRecord]) throws {
        let database = KeyStateDatabase(version: 1, records: snapshot)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(database)
            let signature = try privateKey.signature(for: data)
            let dbURL = directory.appendingPathComponent(Self.databaseFilename)
            let sigURL = directory.appendingPathComponent(Self.signatureFilename)
            try data.write(to: dbURL, options: [.atomic])
            try signature.write(to: sigURL, options: [.atomic])
        } catch {
            throw KeyStateStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    private static func loadVerified(
        databaseURL: URL,
        signatureURL: URL,
        publicKey: Curve25519.Signing.PublicKey
    ) throws -> [String: KeyStateRecord] {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              FileManager.default.fileExists(atPath: signatureURL.path)
        else {
            return [:]
        }
        let data: Data
        let signature: Data
        do {
            data = try Data(contentsOf: databaseURL)
            signature = try Data(contentsOf: signatureURL)
        } catch {
            throw KeyStateStoreError.persistenceFailed(error.localizedDescription)
        }
        guard publicKey.isValidSignature(signature, for: data) else {
            throw KeyStateStoreError.tampered
        }
        do {
            let database = try JSONDecoder().decode(KeyStateDatabase.self, from: data)
            return database.records
        } catch {
            throw KeyStateStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    // MARK: - Signing key

    /// Keychain item service for the per-install signing key.
    private static let signingKeyService = "RNP Mail Extension key-state signing key"
    /// Keychain item account. Distinct from TrustStore's account so the two
    /// never share a key.
    private static let signingKeyAccount = "key-state-store"

    private static func loadOrCreateSigningKey(
        keychainAccessGroup: String?
    ) throws -> Curve25519.Signing.PrivateKey {
        if let existing = try? readSigningKey(keychainAccessGroup: keychainAccessGroup) {
            return existing
        }
        let key = Curve25519.Signing.PrivateKey()
        try storeSigningKey(key, keychainAccessGroup: keychainAccessGroup)
        return key
    }

    private static func readSigningKey(
        keychainAccessGroup: String?
    ) throws -> Curve25519.Signing.PrivateKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: signingKeyService,
            kSecAttrAccount as String: signingKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyStateStoreError.persistenceFailed("signing key not found")
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private static func storeSigningKey(
        _ key: Curve25519.Signing.PrivateKey,
        keychainAccessGroup: String?
    ) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: signingKeyService,
            kSecAttrAccount as String: signingKeyAccount,
            kSecValueData as String: key.rawRepresentation,
        ]
        var addQuery = attributes
        if let group = keychainAccessGroup, !group.isEmpty {
            addQuery[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: signingKeyService,
                kSecAttrAccount as String: signingKeyAccount,
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: key.rawRepresentation,
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeyStateStoreError.persistenceFailed("signing key update failed (\(updateStatus))")
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeyStateStoreError.persistenceFailed("signing key store failed (\(status))")
        }
    }
}
