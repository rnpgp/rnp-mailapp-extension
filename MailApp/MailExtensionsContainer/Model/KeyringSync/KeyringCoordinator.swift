//
//  KeyringCoordinator.swift
//  RNP
//
//  Orchestrates the active canonical `KeyringBackend` and the local
//  `KeyringStore` cache librnp reads from. Owns three responsibilities:
//
//    1. Picks the backend at launch from `SyncConfiguration.canonicalStoreID`.
//    2. Propagates local mutations (generate/import/delete/rotate/...) to
//       the active backend so other devices see them via the backend's
//       own sync (CloudKit subscription, file-watch on the .asc dir).
//    3. Reconciles the local cache when the backend reports a remote
//       change (push from another device, file-sync tool, manual edit).
//
//  Why a coordinator instead of just swapping KeyringStore backends:
//  librnp can only read/write OpenPGP keyring files on disk. CloudKit
//  and per-key .asc directories are not keyring files. So the local
//  keyring file is always the cache; the backend is the source of truth
//  for everything except the default `rnp-local` case where they're
//  the same file. See docs/sync-architecture.md and the plan at
//  ~/.claude/plans/partitioned-snuggling-wren.md.
//
//  Thread-safety: mutations are confined to the main actor (KeysManager
//  is ObservableObject; its mutations run on main). Backend observation
//  callbacks may arrive on background queues; they hop back to main
//  before touching the cache.
//

import Combine
import Foundation
import MailSecurityEngine
import Librnp

public final class KeyringCoordinator {

    /// Process-wide instance, set by `KeysManager.bootstrap`. Read by
    /// UI surfaces that don't have a natural parent chain to thread it
    /// through (e.g. `SyncSettingsSheet` invoked from the Tools hub).
    /// Returns nil before bootstrap completes or when the keyring
    /// directory can't be opened.
    public static var shared: KeyringCoordinator?
    private static let sharedLock = NSLock()

    /// Called by `KeysManager.bootstrap` once the coordinator is built.
    static func setShared(_ coordinator: KeyringCoordinator?) {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        shared = coordinator
    }

    /// Active canonical backend. Behind this property: a single
    /// reference. Swapping it via `migrate(to:)` is the only path.
    public private(set) var backend: KeyringBackend

    /// Local keyring file that librnp reads/writes. Always the App
    /// Group container for macOS GUI, `~/.rnp/` for CLI. When the
    /// canonical backend is `rnp-local`, this IS the backend's file.
    public let localCache: KeyringStore

    public let config: SyncConfiguration

    private var observer: AnyCancellable?
    private let propagateSubject = PassthroughSubject<PropagationEvent, Never>()

    /// Fingerprints the backend reported the last time we saw a
    /// non-empty remote snapshot. Used by `reconcileLocalCache` to
    /// detect deletions without flagging every key on a transient
    /// empty read (network blip, iCloud briefly unavailable).
    private var lastNonEmptyRemoteFprs: Set<String> = []
    /// Fingerprints the user has not yet decided about. Populated when
    /// the backend reports a snapshot missing a key it previously had.
    /// Cleared per-fingerprint by `resolveRemoteDeletion`.
    @Published public private(set) var pendingRemoteDeletions: Set<String> = []

    /// Stream of propagate attempts (success + failure). UI surfaces
    /// failures as a non-blocking banner; tests use it for assertions.
    public var propagationEvents: AnyPublisher<PropagationEvent, Never> {
        propagateSubject.eraseToAnyPublisher()
    }

    private init(config: SyncConfiguration, backend: KeyringBackend, localCache: KeyringStore) {
        self.config = config
        self.backend = backend
        self.localCache = localCache
        startObservingBackend()
    }

    // MARK: - Factory

    /// Builds the coordinator for this process. Returns nil when the
    /// local cache can't be opened (keyring directory unreadable); in
    /// that case the app launches in degraded mode with no coordinator.
    public static func make(directory: URL) -> KeyringCoordinator? {
        guard let cache = SharedKeyring.makeKeyringStore(directory: directory) else {
            return nil
        }
        let config = SyncConfiguration()
        let backend = makeBackend(for: config, cache: cache)
        return KeyringCoordinator(config: config, backend: backend, localCache: cache)
    }

    /// Maps the user's `canonicalStoreID` to a concrete backend.
    /// All three options are wired: local file (default), per-key
    /// `.asc` directory, and CloudKit. The CloudKit backend reads
    /// `CKContainer.default()` so iCloud sign-in must be active on
    /// the user's Mac for it to be `.available`.
    public static func makeBackend(for config: SyncConfiguration, cache: KeyringStore) -> KeyringBackend {
        switch config.canonicalStoreID {
        case "rnp-asc-dir":
            let url = URL(fileURLWithPath: config.perKeyDirectoryPath, isDirectory: true)
            return PerKeyDirectoryKeyringBackend(directory: url)
        case "rnp-cloudkit":
            return CloudKitKeyringBackend()
        default:
            return LocalFileKeyringBackend(directory: AppGroup.keyringDirectory(), cache: cache)
        }
    }

    // MARK: - Propagation (local mutation → backend)

    public enum PropagationEvent {
        case upserted(fingerprint: String)
        case deleted(fingerprint: String)
        case failed(fingerprint: String, message: String)
    }

    /// Called by `KeysManager.perform` after a mutation. Emits one
    /// event per fingerprint that differs between `before` and `after`
    /// (new = upsert, removed = delete). Unchanged fingerprints that
    /// exist in both sets still get re-propagated when their bytes
    /// changed (subkey rotation, expiry extension, revocation sig) —
    /// we detect that by comparing the exported bytes.
    public func propagate(before: Set<String>, after: Set<String>) {
        // Removed: emit delete for anything that was in `before` and
        // isn't in `after`.
        for fpr in before where !after.contains(fpr) {
            propagateDelete(fingerprint: fpr)
        }
        // Upsert: every fingerprint still present. Bytes-diff check
        // inside `propagateUpsert` skips no-op writes.
        for fpr in after {
            propagateUpsert(fingerprint: fpr, skipIfUnchanged: before.contains(fpr))
        }
    }

    /// Convenience for callers that only have one new fingerprint
    /// (e.g. import flow that just added one key).
    public func propagateUpsert(fingerprint: String) {
        propagateUpsert(fingerprint: fingerprint, skipIfUnchanged: false)
    }

    private func propagateUpsert(fingerprint: String, skipIfUnchanged: Bool) {
        // rnp-local: backend is the local file. No external write needed.
        if backend.identifier == "rnp-local" {
            propagateSubject.send(.upserted(fingerprint: fingerprint))
            return
        }
        let record = makeRecord(fingerprint: fingerprint)
        guard let record else {
            propagateSubject.send(.failed(fingerprint: fingerprint,
                                          message: "Could not export key for backend sync"))
            return
        }
        if skipIfUnchanged, let existing = existingBytes(for: fingerprint), existing == record.keyBytes {
            propagateSubject.send(.upserted(fingerprint: fingerprint))
            return
        }
        do {
            try backend.upsert(record)
            propagateSubject.send(.upserted(fingerprint: fingerprint))
        } catch {
            propagateSubject.send(.failed(fingerprint: fingerprint, message: error.localizedDescription))
        }
    }

    private func propagateDelete(fingerprint: String) {
        if backend.identifier == "rnp-local" {
            propagateSubject.send(.deleted(fingerprint: fingerprint))
            return
        }
        do {
            try backend.delete(fingerprint: fingerprint)
            propagateSubject.send(.deleted(fingerprint: fingerprint))
        } catch {
            propagateSubject.send(.failed(fingerprint: fingerprint, message: error.localizedDescription))
        }
    }

    // MARK: - Migration (user changes canonical store)

    /// Switches the active backend to one matching `newStoreID`.
    /// Copies every key from the local cache into the new backend
    /// before flipping the reference. The local cache is never wiped
    /// — switching back keeps everything the user had.
    ///
    /// Returns the count of records copied. Throws if the new backend
    /// can't accept the writes; in that case the active backend is
    /// left unchanged.
    @discardableResult
    public func migrate(to newStoreID: String) throws -> Int {
        let oldBackend = backend
        let newBackend: KeyringBackend
        switch newStoreID {
        case "rnp-asc-dir":
            let url = URL(fileURLWithPath: config.perKeyDirectoryPath, isDirectory: true)
            newBackend = PerKeyDirectoryKeyringBackend(directory: url)
        case "rnp-cloudkit":
            newBackend = CloudKitKeyringBackend()
        default:
            newBackend = LocalFileKeyringBackend(directory: AppGroup.keyringDirectory(), cache: localCache)
        }

        // If migrating to the same backend type, no-op.
        if newBackend.identifier == oldBackend.identifier {
            return 0
        }

        // Always read from the local cache (authoritative) rather than
        // oldBackend.load() — LocalFileKeyringBackend caches a snapshot
        // at init time and doesn't auto-refresh when the underlying
        // keyring changes, so it would return stale (possibly empty)
        // data here.
        let records = localRecords()
        var copied = 0
        for record in records {
            // Never lose data on migration — wrap each upsert in try?.
            // A failed single record shouldn't roll back the whole thing.
            do {
                try newBackend.upsert(record)
                copied += 1
            } catch {
                propagateSubject.send(.failed(fingerprint: record.id, message: error.localizedDescription))
            }
        }

        // Flip the reference + restart the observer.
        observer?.cancel()
        observer = nil
        backend = newBackend
        config.canonicalStoreID = newStoreID
        startObservingBackend()
        return copied
    }

    // MARK: - Remote-change reconciliation

    /// Subscribes to the backend's change stream and re-imports new
    /// keys into the local cache when a remote change arrives (push
    /// from another device, file-sync tool rewrote the .asc dir).
    ///
    /// Additive for new keys; deletions are flagged in
    /// `pendingRemoteDeletions` for the review sheet — they are NOT
    /// auto-applied to the local cache. That matches the "never wipe
    /// user keys" rule.
    private func startObservingBackend() {
        observer = backend.observeChanges { [weak self] records in
            guard let self else { return }
            DispatchQueue.main.async {
                self.reconcileLocalCache(with: records)
            }
        }
    }

    private func reconcileLocalCache(with records: [KeyringKeyRecord]) {
        // rnp-local: backend and cache are the same file. Nothing to do.
        if backend.identifier == "rnp-local" { return }
        let remoteFprs = Set(records.map(\.id))
        let localFprs = Set(((try? localCache.listKeys()) ?? []).map(\.fingerprint))

        // Additive: import any new remote keys.
        for record in records where !localFprs.contains(record.id) {
            do {
                _ = try localCache.importKeys(record.keyBytes)
            } catch {
                propagateSubject.send(.failed(fingerprint: record.id, message: error.localizedDescription))
            }
        }

        // Deletion detection: only flag fingerprints that the backend
        // *previously* had and now doesn't. An empty remote snapshot
        // (network blip, iCloud offline) doesn't trigger false
        // positives because `lastNonEmptyRemoteFprs` was non-empty
        // before — we just don't update it on empty reads.
        if remoteFprs.isEmpty {
            return
        }
        let disappeared = lastNonEmptyRemoteFprs.subtracting(remoteFprs)
        for fpr in disappeared where localFprs.contains(fpr) {
            pendingRemoteDeletions.insert(fpr)
        }
        lastNonEmptyRemoteFprs = remoteFprs
    }

    /// User resolved a remote-deletion prompt. `deleteLocally == true`
    /// removes the key from the local cache (and from any rnp-local
    /// backend); `false` just dismisses the prompt — the key stays
    /// locally and will be re-propagated to the backend on the next
    /// mutation that touches it.
    public func resolveRemoteDeletion(_ fingerprint: String, deleteLocally: Bool) {
        pendingRemoteDeletions.remove(fingerprint)
        guard deleteLocally else { return }
        do {
            try localCache.deleteKey(fingerprint: fingerprint)
        } catch let error as RnpError {
            if case .keyNotFound = error { return }
            propagateSubject.send(.failed(fingerprint: fingerprint, message: error.localizedDescription))
        } catch {
            propagateSubject.send(.failed(fingerprint: fingerprint, message: error.localizedDescription))
        }
    }

    // MARK: - Helpers

    /// Builds a `KeyringKeyRecord` for `fingerprint` from the local
    /// cache. Exports secret bytes when the key has a secret; falls
    /// back to public bytes otherwise. Returns nil when the
    /// fingerprint isn't in the cache or the export fails.
    private func makeRecord(fingerprint: String) -> KeyringKeyRecord? {
        let infos = (try? localCache.listKeys()) ?? []
        guard let info = infos.first(where: { $0.fingerprint == fingerprint }) else { return nil }
        let bytes: Data
        if info.hasSecret, let secret = try? localCache.exportKey(fingerprint: fingerprint, secret: true) {
            bytes = secret
        } else if let pub = try? localCache.exportKey(fingerprint: fingerprint) {
            bytes = pub
        } else {
            return nil
        }
        return KeyringKeyRecord(
            id: fingerprint,
            primaryUserID: info.primaryUserID,
            allUserIDs: info.userIDs,
            keyBytes: bytes,
            hasSecret: info.hasSecret,
            keyCreationDate: info.creationDate,
            keyExpirationDate: info.expirationDate,
            modifiedAt: Date(),
            modifiedBy: Host.current().localizedName ?? "mac"
        )
    }

    /// Reads the backend's current bytes for `fingerprint`, when the
    /// backend already has the key. Used by `propagateUpsert` to skip
    /// no-op writes (e.g. after a reload that didn't actually change
    /// the bytes).
    private func existingBytes(for fingerprint: String) -> Data? {
        guard let records = try? backend.load() else { return nil }
        return records.first(where: { $0.id == fingerprint })?.keyBytes
    }

    private func localRecords() -> [KeyringKeyRecord] {
        let infos = (try? localCache.listKeys()) ?? []
        return infos.compactMap { makeRecord(fingerprint: $0.fingerprint) }
    }
}
