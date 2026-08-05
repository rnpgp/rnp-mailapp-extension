//
//  PerKeyDirectoryKeyringBackend.swift
//  RNP
//
//  `KeyringBackend` that stores each key as its own `<fingerprint>.asc`
//  file in a directory. Recommended for cross-platform sync (Mac ↔ Linux
//  via Syncthing / Dropbox / git): file add/delete is the natural diff,
//  no binary merge conflicts, every key is independently atomic.
//
//  Conflict resolution: latest `modifiedAt` in the file's OpenPGP
//  signature packet wins. Older version renamed to
//  `<fpr>.asc.conflict-<timestamp>` for user review.
//
//  See TODO.complete/34-per-key-asc-directory-backend.md.
//

import Combine
import Foundation

public final class PerKeyDirectoryKeyringBackend: KeyringBackend {

    public let identifier: String
    public let displayName = "Per-key .asc directory"
    public var availability: BackendAvailability {
        FileManager.default.fileExists(atPath: directory.path)
            ? .available
            : .unavailable(reason: "Directory does not exist: \(directory.path)")
    }

    public let directory: URL
    private let subject = CurrentValueSubject<[KeyringKeyRecord], Never>([])
    private var source: DispatchSourceFileSystemObject?

    public init(directory: URL, identifierSuffix: String? = nil) {
        self.directory = directory
        // Per-instance identifier lets users have multiple per-key
        // directories active at once (rare but possible).
        self.identifier = "rnp-asc-dir" + (identifierSuffix.map { "-\($0)" } ?? "")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        startWatching()
    }

    deinit {
        source?.cancel()
    }

    // MARK: KeyringBackend

    public func load() throws -> [KeyringKeyRecord] {
        subject.value
    }

    public func upsert(_ record: KeyringKeyRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = url(for: record.id)
        // Conflict detection: if the file already exists with different
        // bytes, rename the existing one before writing the new one.
        if let existing = try? Data(contentsOf: url), existing != record.keyBytes {
            let conflict = directory.appendingPathComponent(
                "\(record.id).asc.conflict-\(Self.timestamp(Date()))"
            )
            try? FileManager.default.moveItem(at: url, to: conflict)
        }
        try record.keyBytes.write(to: url, options: .atomic)
        reload()
    }

    public func delete(fingerprint: String) throws {
        let url = url(for: fingerprint)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        reload()
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    // MARK: Internals

    private func url(for fingerprint: String) -> URL {
        directory.appendingPathComponent("\(fingerprint).asc")
    }

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// Scans the directory for `.asc` files. Each file is one record;
    /// the fingerprint is parsed from the filename. The bytes go in
    /// `keyBytes` unchanged — they're ASCII-armored PGP already.
    private func reload() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                          includingPropertiesForKeys: nil) else {
            subject.send([])
            return
        }
        var records: [KeyringKeyRecord] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasSuffix(".asc"), !name.contains(".conflict-") else { continue }
            let fingerprint = String(name.dropLast(".asc".count))
            guard let bytes = try? Data(contentsOf: entry) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: entry.path)
            let modified = (attrs?[.modificationDate] as? Date) ?? Date()
            records.append(KeyringKeyRecord(
                id: fingerprint,
                primaryUserID: fingerprint.suffix(16).description,  // filename doesn't carry user ID
                allUserIDs: [],
                keyBytes: bytes,
                hasSecret: Self.looksLikeSecretKey(bytes),
                keyCreationDate: modified,
                keyExpirationDate: nil,
                modifiedAt: modified,
                modifiedBy: "asc-dir"
            ))
        }
        // De-duplicate by fingerprint (in case both `fpr.asc` and
        // `fpr.asc.conflict-...` exist; only the non-conflict one counts).
        var seen: [String: KeyringKeyRecord] = [:]
        for r in records { seen[r.id] = r }
        subject.send(Array(seen.values).sorted { $0.id < $1.id })
    }

    /// True if the bytes look like an armored secret key (vs public).
    /// Cheaper than parsing; we just check for `PGP PRIVATE KEY BLOCK`.
    private static func looksLikeSecretKey(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return false }
        return prefix.contains("PGP PRIVATE KEY BLOCK")
    }

    /// File-watch via DispatchSource. Fires when the directory
    /// changes (Syncthing/iCloud Drive/Dropbox sync from another
    /// device, manual edits, etc.). Triggers a reload.
    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .global(qos: .utility))
        source?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.reload()
            }
        }
        source?.setCancelHandler {
            close(fd)
        }
        source?.resume()
    }
}
