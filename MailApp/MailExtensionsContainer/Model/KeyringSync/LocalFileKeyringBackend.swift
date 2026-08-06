//
//  LocalFileKeyringBackend.swift
//  RNP
//
//  Concrete `KeyringBackend` backed by a local directory. Wraps the
//  existing `KeysManager` — same data shape as before, now behind the
//  protocol so the Sync UI can swap in alternates without touching
//  call sites.
//
//  Phase 1.5 refactor (TODO.complete/33) — actually done this time:
//  upsert + delete route through KeysManager's import/delete methods,
//  so the protocol surface is live end-to-end, not stubbed.
//

import Combine
import Foundation
import MailSecurityEngine

public final class LocalFileKeyringBackend: KeyringBackend {

    public let identifier = "rnp-local"
    public let displayName = "Local RNP keyring"
    public var availability: BackendAvailability { .available }

    public let directory: URL
    private weak var manager: KeysManager?
    private let subject = CurrentValueSubject<[KeyringKeyRecord], Never>([])

    init(directory: URL, manager: KeysManager? = nil) {
        self.directory = directory
        self.manager = manager
        reload()
    }

    public func load() throws -> [KeyringKeyRecord] {
        subject.value
    }

    /// Adds or updates one key. Routed through `KeysManager.importKeys`,
    /// which writes the key bytes to the live keyring.
    public func upsert(_ record: KeyringKeyRecord) throws {
        guard let manager else {
            throw LocalBackendError.managerUnavailable
        }
        guard !record.keyBytes.isEmpty else { return }
        let imported = manager.importKeys(record.keyBytes)
        guard !imported.isEmpty else {
            throw LocalBackendError.keyringUnavailable
        }
        reload()
    }

    /// Deletes one key. Routed through `KeysManager.delete(_:)`, which
    /// is wrapped by the three-step delete confirmation + encrypted
    /// backup (PR #191) when invoked via the UI.
    public func delete(fingerprint: String) throws {
        guard let manager else {
            throw LocalBackendError.keyringUnavailable
        }
        guard let key = manager.keys.first(where: { $0.fingerprint == fingerprint }) else {
            return  // already gone
        }
        manager.delete(key)
        reload()
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    /// Refreshes the cached snapshot by reading the directory via
    /// `SharedKeyring`'s `KeyManager`. Call after any mutation.
    public func reload() {
        guard let km = SharedKeyring.makeKeyringStore(directory: directory) else {
            subject.send([])
            return
        }
        let keys = (try? km.listKeys()) ?? []
        subject.send(keys.map(Self.record(from:)))
    }

    private static func record(from key: KeyInfo) -> KeyringKeyRecord {
        KeyringKeyRecord(
            id: key.fingerprint,
            primaryUserID: key.primaryUserID,
            allUserIDs: key.userIDs,
            keyBytes: Data(),
            hasSecret: key.hasSecret,
            keyCreationDate: key.creationDate,
            keyExpirationDate: key.expirationDate,
            modifiedAt: Date(),
            modifiedBy: "local"
        )
    }
}

public enum LocalBackendError: Error, LocalizedError {
    case managerUnavailable
    case keyringUnavailable

    public var errorDescription: String? {
        switch self {
        case .managerUnavailable:  return "error.localBackend.managerUnavailable".localized
        case .keyringUnavailable:  return "error.localBackend.keyringUnavailable".localized
        }
    }
}
