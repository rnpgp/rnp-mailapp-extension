//
//  CompositeKeyringBackend.swift
//  RNP
//
//  Unifies multiple `KeyringBackend`s into a single view. The UI
//  binds to one of these; underneath, keys may live in a local
//  directory, iCloud CloudKit, or both.
//
//  Composite has ONE primary sink for writes (the user's chosen
//  canonical store) but reads from every active source so the UI
//  shows the union.
//
//  Import sources (GnuPG, WKD, etc.) are NOT in here — those are
//  `KeyImportSource` and feed into the import flow separately.
//
//  See docs/sync-architecture.md.
//

import Combine
import Foundation

public final class CompositeKeyringBackend: KeyringBackend {

    public let identifier = "composite"
    public let displayName = "Composite (all active RNP stores)"
    public var availability: BackendAvailability {
        // Available iff at least one source is available.
        sources.contains { $0.availability == .available }
            ? .available
            : .unavailable(reason: "No keyring backend available")
    }

    /// Active sources (read from). Order doesn't matter for reads —
    /// the composite unifies by fingerprint.
    public private(set) var sources: [KeyringBackend]

    /// The single sink for writes. Must be one of `sources`. Defaults
    /// to the first source; user-changed via Sync UI.
    public private(set) var primarySink: KeyringBackend

    private var observers: [AnyCancellable] = []
    private let subject = CurrentValueSubject<[KeyringKeyRecord], Never>([])

    public init(sources: [KeyringBackend], primarySink: KeyringBackend? = nil) {
        assert(!sources.isEmpty, "CompositeKeyringBackend requires at least one source")
        self.sources = sources
        self.primarySink = primarySink ?? sources[0]
        assert(sources.contains { $0 === self.primarySink }, "primarySink must be one of sources")
        reloadFromSources()
        observeAllSources()
    }

    public func load() throws -> [KeyringKeyRecord] {
        subject.value
    }

    /// Writes go to the primary sink only. Import sources are not
    /// in the composite so they can't be hit by this.
    public func upsert(_ record: KeyringKeyRecord) throws {
        try primarySink.upsert(record)
        reloadFromSources()
    }

    /// Deletes from every source that has the key. The user's GnuPG
    /// keyring is NOT a source — it's an `KeyImportSource` and has no
    /// delete method — so this can never reach ~/.gnupg.
    public func delete(fingerprint: String) throws {
        for source in sources {
            try? source.delete(fingerprint: fingerprint)
        }
        reloadFromSources()
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    // MARK: Internals

    private func reloadFromSources() {
        let records = sources.compactMap { try? $0.load() }.flatMap { $0 }
        // Unify by fingerprint: same fingerprint from multiple sources
        // collapses to one record (last-write-wins on byte differences).
        var seen: [String: KeyringKeyRecord] = [:]
        for record in records {
            seen[record.id] = record
        }
        let unified = Array(seen.values).sorted { $0.primaryUserID < $1.primaryUserID }
        subject.send(unified)
    }

    private func observeAllSources() {
        observers = sources.map { source in
            source.observeChanges { [weak self] _ in
                self?.reloadFromSources()
            }
        }
    }
}
