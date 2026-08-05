//
//  LocalFileKeyringBackend.swift
//  RNP
//
//  Concrete `KeyringBackend` backed by a local directory. This is
//  the current behavior — App Group container on macOS — now behind
//  the protocol so we can swap in a CloudKit-backed store without
//  touching the call sites.
//
//  Cross-platform: works on both macOS and iOS. The App Group path
//  resolves differently per platform but FileManager calls work
//  identically.
//

import Combine
import Foundation

public final class LocalFileKeyringBackend: KeyringBackend {

    public let identifier = "rnp-local"
    public let displayName = "Local RNP keyring"
    public var availability: BackendAvailability { .available }

    private let directory: URL
    private let fileManager: FileManager
    private let subject: CurrentValueSubject<[KeyringKeyRecord], Never>

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.subject = CurrentValueSubject([])
    }

    public func load() throws -> [KeyringKeyRecord] {
        // Local file keyring doesn't currently keep per-key records;
        // it stores pubring/secring as binary blobs. The Phase 1
        // refactor of SharedKeyring will populate this with parsed
        // records via KeyManager.listKeys(). For now, return empty —
        // callers continue to use SharedKeyring directly.
        return []
    }

    public func upsert(_ record: KeyringKeyRecord) throws {
        // Phase 1 refactor will route this through KeyManager's import
        // path. For now, no-op — callers use SharedKeyring directly.
    }

    public func delete(fingerprint: String) throws {
        // Phase 1 refactor will route this through KeyManager's
        // delete path. For now, no-op.
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    /// Back-compat: existing code reads the keyring directory directly.
    /// This accessor preserves that path during the Phase 1 migration.
    public var keyringDirectory: URL { directory }
}
