//
//  SignedJSONStore.swift
//  KeyStateStore
//
//  Generic signed-JSON persistence: encode → sign → write, and
//  read → verify → decode. Fail-closed on tamper. Encapsulates the
//  load-or-create Ed25519 Keychain signing key pattern that was
//  previously copy-pasted across TrustStore, KeyStateStore, and
//  SecurityStateRecordStore.
//
//  **Deletion test**: if this module is deleted, the sign/verify/
//  persist loop reappears in every store that needs tamper-evident
//  JSON — currently 3, with different bugs in each copy. Keeping it
//  concentrates the signing logic, the Keychain key management, and
//  the atomic-write semantics in one tested place.
//

import CryptoKit
import Foundation
import Security

/// Errors thrown by `SignedJSONStore`.
public enum SignedJSONStoreError: Error, Equatable {
    case persistenceFailed(String)
    case tampered
}

/// Generic tamper-evident JSON store backed by an Ed25519-signed
/// file pair (`<db>.json` + `<db>.json.sig`) in a directory.
///
/// The signing key lives in the Keychain, identified by `service`
/// + `account`. Each store should use a distinct pair so a
/// compromise of one store's key does not forge another's records.
///
/// **Depth**: the interface is `load() -> T?` and `save(T)`. The
/// implementation handles Keychain key lifecycle, JSON
/// encoding/decoding, Ed25519 sign/verify, atomic writes, and
/// fail-closed-on-tamper semantics — substantial leverage behind a
/// two-method interface.
public final class SignedJSONStore<T: Codable> {
    public let directory: URL
    public let databaseFilename: String
    public let signatureFilename: String
    public let privateKey: Curve25519.Signing.PrivateKey

    private let lock = NSLock()
    private var cache: T?

    /// Creates the store, creating the directory and loading any
    /// existing signed database.
    public init(
        directory: URL,
        databaseFilename: String,
        signatureFilename: String,
        keychainService: String,
        keychainAccount: String,
        keychainAccessGroup: String? = Bundle.main.object(forInfoDictionaryKey: "RNPMAILKeychainAccessGroup") as? String
    ) throws {
        self.directory = directory
        self.databaseFilename = databaseFilename
        self.signatureFilename = signatureFilename
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = try KeychainSigningKeyHelper.loadOrCreate(
            service: keychainService,
            account: keychainAccount,
            keychainAccessGroup: keychainAccessGroup
        )
        self.privateKey = key
        // Eagerly verify existing data during init so tamper is
        // detected at construction time, matching the behavior the
        // existing callers and tests expect.
        if let verified = try load() {
            cache = verified
        }
    }

    /// Returns the decoded value, verifying the signature. Returns
    /// `nil` when no database file exists. Throws `.tampered` when
    /// the signature does not verify.
    public func load() throws -> T? {
        lock.lock()
        if let cache {
            lock.unlock()
            return cache
        }
        lock.unlock()

        let dbURL = directory.appendingPathComponent(databaseFilename)
        let sigURL = directory.appendingPathComponent(signatureFilename)
        guard FileManager.default.fileExists(atPath: dbURL.path),
              FileManager.default.fileExists(atPath: sigURL.path)
        else { return nil }

        let data: Data
        let signature: Data
        do {
            data = try Data(contentsOf: dbURL)
            signature = try Data(contentsOf: sigURL)
        } catch {
            throw SignedJSONStoreError.persistenceFailed(error.localizedDescription)
        }
        guard privateKey.publicKey.isValidSignature(signature, for: data) else {
            throw SignedJSONStoreError.tampered
        }
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            lock.lock(); cache = value; lock.unlock()
            return value
        } catch {
            throw SignedJSONStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Encodes the value to JSON, signs it, and writes both files
    /// atomically.
    public func save(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw SignedJSONStoreError.persistenceFailed(error.localizedDescription)
        }
        let signature: Data
        do {
            signature = try privateKey.signature(for: data)
        } catch {
            throw SignedJSONStoreError.persistenceFailed(error.localizedDescription)
        }
        let dbURL = directory.appendingPathComponent(databaseFilename)
        let sigURL = directory.appendingPathComponent(signatureFilename)
        do {
            try data.write(to: dbURL, options: [.atomic])
            try signature.write(to: sigURL, options: [.atomic])
        } catch {
            throw SignedJSONStoreError.persistenceFailed(error.localizedDescription)
        }
        lock.lock(); cache = value; lock.unlock()
    }
}

// MARK: - KeychainSigningKeyHelper

/// Centralized helper for creating, loading, and updating Ed25519
/// signing keys stored in the macOS Keychain. Used by
/// SignedJSONStore and by stores that manage their own signing
/// (TrustStore, SecurityStateRecordStore).
public enum KeychainSigningKeyHelper {
    public static func loadOrCreate(
        service: String,
        account: String,
        keychainAccessGroup: String?
    ) throws -> Curve25519.Signing.PrivateKey {
        if let existing = try? read(
            service: service,
            account: account,
            keychainAccessGroup: keychainAccessGroup
        ) {
            return existing
        }
        let key = Curve25519.Signing.PrivateKey()
        try store(key, service: service, account: account, keychainAccessGroup: keychainAccessGroup)
        return key
    }

    public static func read(
        service: String,
        account: String,
        keychainAccessGroup: String?
    ) throws -> Curve25519.Signing.PrivateKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw SignedJSONStoreError.persistenceFailed("Keychain read failed: \(status)")
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    public static func store(
        _ key: Curve25519.Signing.PrivateKey,
        service: String,
        account: String,
        keychainAccessGroup: String?
    ) throws {
        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.rawRepresentation,
        ]
        if let group = keychainAccessGroup, !group.isEmpty {
            addQuery[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: key.rawRepresentation,
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SignedJSONStoreError.persistenceFailed("Keychain update failed: \(updateStatus)")
            }
            return
        }
        guard status == errSecSuccess else {
            throw SignedJSONStoreError.persistenceFailed("Keychain store failed: \(status)")
        }
    }
}
