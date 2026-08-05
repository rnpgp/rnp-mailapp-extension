//
//  KeyringBackend.swift
//  RNP
//
//  Read/write protocol for RNP's CANONICAL keyring storage. RNP owns
//  this data; writes go here. Distinct from `KeyImportSource`, which
//  is read-only and never receives writes.
//
//  Cross-platform: this file compiles for both macOS and iOS. The
//  concrete backends (`RNPLocalKeyringBackend`, `RNPCloudKitBackend`)
//  may have platform-specific bits, but the protocol is shared.
//
//  See docs/sync-architecture.md.
//

import Combine
import Foundation

/// Per-key record — what backends exchange. One record per
/// fingerprint; backends unify by id.
public struct KeyringKeyRecord: Equatable, Sendable, Identifiable {
    public let id: String           // fingerprint
    public let primaryUserID: String
    public let allUserIDs: [String]
    public let keyBytes: Data
    public let hasSecret: Bool
    public let keyCreationDate: Date
    public let keyExpirationDate: Date?
    public let modifiedAt: Date
    public let modifiedBy: String

    public init(
        id: String,
        primaryUserID: String,
        allUserIDs: [String],
        keyBytes: Data,
        hasSecret: Bool,
        keyCreationDate: Date,
        keyExpirationDate: Date?,
        modifiedAt: Date,
        modifiedBy: String
    ) {
        self.id = id
        self.primaryUserID = primaryUserID
        self.allUserIDs = allUserIDs
        self.keyBytes = keyBytes
        self.hasSecret = hasSecret
        self.keyCreationDate = keyCreationDate
        self.keyExpirationDate = keyExpirationDate
        self.modifiedAt = modifiedAt
        self.modifiedBy = modifiedBy
    }
}

/// RNP's canonical keyring backend. Writes go here. RNP NEVER writes
/// to `KeyImportSource` — those have no write API.
public protocol KeyringBackend: AnyObject {
    /// Stable identifier for persistence (e.g. "rnp-local", "rnp-cloudkit").
    var identifier: String { get }
    /// User-facing name for the Sync UI.
    var displayName: String { get }
    /// Whether this backend is currently usable on this device.
    var availability: BackendAvailability { get }

    /// Snapshot of every key RNP currently owns.
    func load() throws -> [KeyringKeyRecord]
    /// Add or update one key in RNP's store. Idempotent on fingerprint.
    func upsert(_ record: KeyringKeyRecord) throws
    /// Remove one key from RNP's store. NEVER touches import sources.
    func delete(fingerprint: String) throws

    /// Subscribe to backend-originated changes (CloudKit push from
    /// another device, Syncthing file change of ~/.rnp/). Returns a
    /// cancellable.
    func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable
}
