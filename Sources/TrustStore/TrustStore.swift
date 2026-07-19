//
//  TrustStore.swift
//  swift-rnp
//
//  Tamper-detecting persistence of per-address OpenPGP key trust.
//

import CryptoKit
import Foundation
import os
import Security

/// Errors thrown by `TrustStore`.
public enum TrustStoreError: Error, Equatable {
    /// The trust database could not be read or written.
    case persistenceFailed(String)
    /// The signature on the trust database failed verification; the data may
    /// have been tampered with.
    case tampered
}

/// On-disk representation of the trust database.
private struct TrustDatabase: Codable, Equatable {
    /// Schema version for migration safety.
    var version: Int
    /// Active trust records, keyed by normalized email address.
    var records: [String: TrustRecord]
    /// Unresolved key-change conflicts.
    var conflicts: [TrustConflict]

    init(version: Int = 1, records: [String: TrustRecord] = [:], conflicts: [TrustConflict] = []) {
        self.version = version
        self.records = records
        self.conflicts = conflicts
    }
}

/// Stores and queries per-recipient trust: TOFU first-seen, manual
/// fingerprint verification, and key-change conflict detection.
///
/// The database is persisted as JSON with a detached Ed25519 signature. The
/// signing key is supplied by the caller; a convenience initializer stores and
/// retrieves a per-install key from the Keychain. Tampering with either file
/// causes the store to reset to empty (fail-closed to `unverified`) rather than
/// trust corrupted data.
public final class TrustStore {
    /// File name of the trust database inside the store directory.
    public static let databaseFilename = "trust.json"
    /// File name of the detached Ed25519 signature.
    public static let signatureFilename = "trust.json.sig"

    /// Directory holding `trust.json` and `trust.json.sig`.
    public let directory: URL

    /// Ed25519 private key used to sign the database.
    public let privateKey: Curve25519.Signing.PrivateKey

    private let lock = NSRecursiveLock()
    private var database: TrustDatabase
    private let logger = Logger(subsystem: "com.rnpgp.RnpMail", category: "TrustStore")

    /// Creates a trust store in `directory` using the supplied signing key.
    ///
    /// The directory is created if it does not exist. Any existing database is
    /// loaded and verified; if verification fails, the store resets to empty.
    public init(directory: URL, privateKey: Curve25519.Signing.PrivateKey) throws {
        self.directory = directory
        self.privateKey = privateKey
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.database = try Self.loadVerified(
            directory: directory,
            publicKey: privateKey.publicKey,
            logger: logger
        )
    }

    /// Convenience initializer that uses a per-install Ed25519 signing key
    /// stored in the Keychain.
    ///
    /// If no key exists, one is generated and saved. If reading an existing
    /// key from the Keychain fails, or if a newly generated key cannot be
    /// saved, the initializer throws `TrustStoreError.persistenceFailed`.
    /// This prevents an ephemeral in-process key from silently breaking
    /// cross-process trust verification.
    public convenience init(
        directory: URL,
        keychainAccessGroup: String? = Bundle.main.object(forInfoDictionaryKey: "RNPMAILKeychainAccessGroup") as? String
    ) throws {
        let key = try Self.loadOrCreateSigningKey(keychainAccessGroup: keychainAccessGroup)
        try self.init(directory: directory, privateKey: key)
    }

    // MARK: - Queries

    /// Trust state for the given fingerprint, or `unverified` when unknown.
    public func state(forFpr fingerprint: String) -> TrustState {
        lock.lock()
        defer { lock.unlock() }
        if let record = database.records.values.first(where: { $0.fingerprint == fingerprint }) {
            return record.state
        }
        return .unverified
    }

    /// Trust state for the given email address, or `unverified` when unknown.
    public func state(forEmail email: String) -> TrustState {
        let normalized = Self.normalizeEmail(email)
        lock.lock()
        defer { lock.unlock() }
        return database.records[normalized]?.state ?? .unverified
    }

    /// All unresolved key-change conflicts.
    public func conflicts() -> [TrustConflict] {
        lock.lock()
        defer { lock.unlock() }
        return database.conflicts
    }

    /// Whether the given email address has an unresolved key-change conflict.
    public func hasConflict(forEmail email: String) -> Bool {
        let normalized = Self.normalizeEmail(email)
        lock.lock()
        defer { lock.unlock() }
        return database.conflicts.contains { $0.email == normalized }
    }

    // MARK: - Mutations

    /// Records that `fingerprint` was seen for `email`.
    ///
    /// - If this is the first fingerprint for the address, it is recorded with
    ///   state `unverified` (TOFU).
    /// - If the same fingerprint was already recorded, its `lastSeen` timestamp
    ///   is updated.
    /// - If a different fingerprint was already recorded, a `TrustConflict` is
    ///   created (unless one already exists) and the new fingerprint is marked
    ///   `problem`.
    public func noteSeen(email: String, fingerprint: String) throws {
        let normalized = Self.normalizeEmail(email)
        lock.lock()
        defer { lock.unlock() }

        if let existing = database.records[normalized] {
            if existing.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame {
                var updated = existing
                updated.lastSeen = Date()
                database.records[normalized] = updated
            } else {
                let conflictExists = database.conflicts.contains {
                    $0.email == normalized &&
                    $0.existingFingerprint == existing.fingerprint &&
                    $0.newFingerprint == fingerprint
                }
                if !conflictExists {
                    database.conflicts.append(TrustConflict(
                        email: normalized,
                        existingFingerprint: existing.fingerprint,
                        newFingerprint: fingerprint
                    ))
                }
                // Ensure the new fingerprint has a record in problem state.
                let newRecord = database.records.values.first {
                    $0.email == normalized && $0.fingerprint == fingerprint
                } ?? TrustRecord(email: normalized, fingerprint: fingerprint, state: .problem)
                database.records[normalized] = newRecord
            }
        } else {
            database.records[normalized] = TrustRecord(
                email: normalized,
                fingerprint: fingerprint,
                state: .unverified
            )
        }
        try saveLocked()
    }

    /// Marks the given fingerprint as verified by the user.
    ///
    /// Also resolves any conflicts where this fingerprint is the newly seen
    /// key, so encryption can proceed after the user accepts a key change.
    public func markVerified(fingerprint: String) throws {
        lock.lock()
        defer { lock.unlock() }
        for email in database.records.keys {
            if database.records[email]?.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame {
                database.records[email]?.state = .verified
            }
        }
        database.conflicts.removeAll { $0.newFingerprint == fingerprint }
        try saveLocked()
    }

    /// Marks the given fingerprint as having a problem (expired, revoked, etc).
    public func markProblem(fingerprint: String) throws {
        lock.lock()
        defer { lock.unlock() }
        for email in database.records.keys {
            if database.records[email]?.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame {
                database.records[email]?.state = .problem
            }
        }
        try saveLocked()
    }

    /// Resolves a conflict by accepting `fingerprint` as the new binding for
    /// `email`. The old binding is removed.
    public func resolveConflict(email: String, fingerprint: String) throws {
        let normalized = Self.normalizeEmail(email)
        lock.lock()
        defer { lock.unlock() }
        database.conflicts.removeAll { $0.email == normalized }
        database.records[normalized] = TrustRecord(
            email: normalized,
            fingerprint: fingerprint,
            state: .verified
        )
        try saveLocked()
    }

    // MARK: - Persistence

    private var databaseURL: URL {
        directory.appendingPathComponent(Self.databaseFilename)
    }

    private var signatureURL: URL {
        directory.appendingPathComponent(Self.signatureFilename)
    }

    private func saveLocked() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data: Data
        do {
            data = try encoder.encode(database)
        } catch {
            throw TrustStoreError.persistenceFailed("encode failed: \(error.localizedDescription)")
        }

        do {
            try data.write(to: databaseURL, options: .atomic)
            let signature = try privateKey.signature(for: data)
            try signature.write(to: signatureURL, options: .atomic)
        } catch let error as TrustStoreError {
            throw error
        } catch {
            throw TrustStoreError.persistenceFailed("write failed: \(error.localizedDescription)")
        }
    }

    private static func loadVerified(
        directory: URL,
        publicKey: Curve25519.Signing.PublicKey,
        logger: Logger
    ) throws -> TrustDatabase {
        let databaseURL = directory.appendingPathComponent(databaseFilename)
        let signatureURL = directory.appendingPathComponent(signatureFilename)

        guard let data = FileManager.default.contents(atPath: databaseURL.path),
              let signature = FileManager.default.contents(atPath: signatureURL.path),
              !data.isEmpty,
              !signature.isEmpty
        else {
            return TrustDatabase()
        }

        guard publicKey.isValidSignature(signature, for: data) else {
            logger.error("Trust database signature invalid; resetting to empty")
            return TrustDatabase()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode(TrustDatabase.self, from: data)
            return decoded
        } catch {
            logger.error("Trust database decode failed: \(error.localizedDescription); resetting to empty")
            return TrustDatabase()
        }
    }

    // MARK: - Signing key

    private static let keychainService = "RNP Mail Extension trust signing"
    private static let keychainAccount = "trust-signing-key"

    private static func loadOrCreateSigningKey(keychainAccessGroup: String?) throws -> Curve25519.Signing.PrivateKey {
        let data = try readKeychainData(
            service: keychainService,
            account: keychainAccount,
            accessGroup: keychainAccessGroup
        )
        if let data = data {
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
                throw TrustStoreError.persistenceFailed("Trust signing key in Keychain is corrupt")
            }
            return key
        }

        let key = Curve25519.Signing.PrivateKey()
        try storeKeychainData(
            key.rawRepresentation,
            service: keychainService,
            account: keychainAccount,
            accessGroup: keychainAccessGroup
        )
        return key
    }

    // MARK: - Helpers

    private static func normalizeEmail(_ email: String) -> String {
        email.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Keychain helpers

/// Reads a single generic-password item from the Keychain.
/// - Returns: the stored data, or `nil` if no item exists.
/// - Throws: `TrustStoreError.persistenceFailed` if the Keychain query fails.
private func readKeychainData(service: String, account: String, accessGroup: String?) throws -> Data? {
    var query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: account,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
    ]
    if let accessGroup = accessGroup {
        query[kSecAttrAccessGroup] = accessGroup
    }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
        return nil
    }
    guard status == errSecSuccess else {
        throw TrustStoreError.persistenceFailed("Keychain read failed (status \(status))")
    }
    guard let data = item as? Data else {
        throw TrustStoreError.persistenceFailed("Keychain read succeeded but returned no data")
    }
    return data
}

/// Stores a generic-password item in the Keychain, replacing any existing item.
/// - Throws: `TrustStoreError.persistenceFailed` if the Keychain write fails.
private func storeKeychainData(_ data: Data, service: String, account: String, accessGroup: String?) throws {
    var deleteQuery: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: account,
    ]
    if let accessGroup = accessGroup {
        deleteQuery[kSecAttrAccessGroup] = accessGroup
    }
    SecItemDelete(deleteQuery as CFDictionary)

    var item: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: account,
        kSecValueData: data,
        kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
    ]
    if let accessGroup = accessGroup {
        item[kSecAttrAccessGroup] = accessGroup
    }
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw TrustStoreError.persistenceFailed("Keychain write failed (status \(status))")
    }
}
