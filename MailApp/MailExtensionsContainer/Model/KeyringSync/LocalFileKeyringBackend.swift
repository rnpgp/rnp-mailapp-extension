//
//  LocalFileKeyringBackend.swift
//  RNP
//
//  Concrete `KeyringBackend` backed by a local directory. Wraps the
//  existing `SharedKeyring` factory + `KeyManager.listKeys()` — same
//  data shape as before, now behind the protocol so the Sync UI can
//  swap in alternates (CloudKit, per-key dir) without touching call
//  sites.
//
//  Phase 1.5 refactor (TODO.complete/33).
//

import Combine
import Foundation
import MailSecurityEngine

public final class LocalFileKeyringBackend: KeyringBackend {

    public let identifier = "rnp-local"
    public let displayName = "Local RNP keyring"
    public var availability: BackendAvailability { .available }

    public let directory: URL
    private let subject = CurrentValueSubject<[KeyringKeyRecord], Never>([])
    private var observer: AnyCancellable?

    public init(directory: URL) {
        self.directory = directory
        reload()
    }

    public func load() throws -> [KeyringKeyRecord] {
        subject.value
    }

    /// Local-file backend doesn't keep per-key records separate from
    /// the binary keyring. The full keyring is rewritten through the
    /// existing KeysManager.import path. Upsert here is a no-op for
    /// now; new keys land via KeysManager.importData(_:) which calls
    /// into the underlying KeyManager. The protocol surface exists
    /// so the Sync UI can list this backend as an option.
    public func upsert(_ record: KeyringKeyRecord) throws {
        // No-op for back-compat. Callers continue to use
        // KeysManager.importData(_:) which writes to the same
        // directory this backend reads from.
    }

    public func delete(fingerprint: String) throws {
        // No-op — same reason as upsert. Callers use the
        // DeletionConfirmationState + KeysManager.delete flow which
        // already saves an encrypted backup (PR #191).
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    /// Refreshes the cached snapshot by reading the directory via
    /// SharedKeyring's KeyManager. Called on init and (in future)
    /// when a file-watch notification fires.
    public func reload() {
        guard let km = SharedKeyring.makeKeyManager(directory: directory) else {
            subject.send([])
            return
        }
        let keys = (try? km.listKeys()) ?? []
        let records = keys.map(Self.record(from:))
        subject.send(records)
    }

    /// Translates the engine-layer `KeyInfo` into the protocol-layer
    /// `KeyringKeyRecord`. Same data shape; the protocol version is
    /// storage-agnostic.
    private static func record(from key: KeyInfo) -> KeyringKeyRecord {
        KeyringKeyRecord(
            id: key.fingerprint,
            primaryUserID: key.primaryUserID,
            allUserIDs: key.userIDs,
            keyBytes: Data(),  // bytes fetched on demand at export/import time
            hasSecret: key.hasSecret,
            keyCreationDate: key.creationDate,
            keyExpirationDate: key.expirationDate,
            modifiedAt: Date(),
            modifiedBy: "local"
        )
    }
}
