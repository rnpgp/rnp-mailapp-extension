//
//  LocalFileKeyringBackend.swift
//  RNP
//
//  Concrete `KeyringBackend` backed by a local file on disk. Wraps a
//  `KeyringStore` directly — same librnp keyring file RNP has always
//  used, now behind the protocol so the Sync UI can swap in alternates
//  without touching call sites.
//
//  This is the default canonical store. When the user switches to the
//  per-key `.asc` directory or CloudKit, the new backend becomes the
//  canonical sink and the local file becomes a materialized cache
//  librnp still reads from; see `KeyringCoordinator`.
//

import Combine
import Foundation
import MailSecurityEngine
import Rnp

public final class LocalFileKeyringBackend: KeyringBackend {

    public let identifier = "rnp-local"
    public let displayName = "Local RNP keyring"
    public var availability: BackendAvailability { .available }

    public let directory: URL
    private let cache: KeyringStore?
    private let subject = CurrentValueSubject<[KeyringKeyRecord], Never>([])

    /// - Parameter cache: the `KeyringStore` librarp uses for the same
    ///   file. When non-nil, reads + exports go through it so the
    ///   backend and the engine always see the same in-memory state.
    ///   When nil (e.g. the App Group directory cannot be opened), the
    ///   backend reports an empty keyring.
    public init(directory: URL, cache: KeyringStore? = nil) {
        self.directory = directory
        self.cache = cache ?? SharedKeyring.makeKeyringStore(directory: directory)
        reload()
    }

    public func load() throws -> [KeyringKeyRecord] {
        subject.value
    }

    /// Imports the armored key bytes via the underlying `KeyringStore`.
    /// Used by `KeyringCoordinator` to mirror remote changes back into
    /// the local cache, and by tests that want to seed the backend.
    public func upsert(_ record: KeyringKeyRecord) throws {
        guard let cache else {
            throw LocalBackendError.keyringUnavailable
        }
        guard !record.keyBytes.isEmpty else { return }
        _ = try cache.importKeys(record.keyBytes)
        reload()
    }

    /// Deletes one key by fingerprint. Idempotent — returns silently if
    /// the fingerprint is no longer present.
    public func delete(fingerprint: String) throws {
        guard let cache else {
            throw LocalBackendError.keyringUnavailable
        }
        do {
            try cache.deleteKey(fingerprint: fingerprint)
        } catch let error as RnpError {
            // `.keyNotFound` is a no-op for delete; anything else re-throws.
            if case .keyNotFound = error { return }
            throw error
        }
        reload()
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    /// Refreshes the cached snapshot from the local file. Reads every
    /// fingerprint, exports its current bytes (public, or secret when
    /// available), and emits the result.
    public func reload() {
        guard let cache else {
            subject.send([])
            return
        }
        let infos = (try? cache.listKeys()) ?? []
        let records = infos.compactMap { Self.record(from: $0, cache: cache) }
        subject.send(records)
    }

    private static func record(from key: KeyInfo, cache: KeyringStore) -> KeyringKeyRecord? {
        let bytes: Data
        if key.hasSecret, let secret = try? cache.exportKey(fingerprint: key.fingerprint, secret: true) {
            bytes = secret
        } else if let pub = try? cache.exportKey(fingerprint: key.fingerprint) {
            bytes = pub
        } else {
            return nil
        }
        return KeyringKeyRecord(
            id: key.fingerprint,
            primaryUserID: key.primaryUserID,
            allUserIDs: key.userIDs,
            keyBytes: bytes,
            hasSecret: key.hasSecret,
            keyCreationDate: key.creationDate,
            keyExpirationDate: key.expirationDate,
            modifiedAt: Date(),
            modifiedBy: "local"
        )
    }
}

public enum LocalBackendError: Error, LocalizedError {
    case keyringUnavailable

    public var errorDescription: String? {
        switch self {
        case .keyringUnavailable: return "error.localBackend.keyringUnavailable".localized
        }
    }
}
