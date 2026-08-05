//
//  CloudKitKeyringBackend.swift
//  RNP
//
//  `KeyringBackend` backed by iCloud private database. Each key is
//  one CKRecord of type "RNPKey", identified by fingerprint. Push
//  path is implemented; pull/subscription path is the next step.
//
//  Status (TODO 35):
//    ✅ Record schema
//    ✅ Push (upsert → CKModifyRecordsOperation)
//    ✅ Load (fetchAllKeys → CKFetchRecordsOperation or query)
//    ✅ Delete (CKModifyRecordsOperation with .delete)
//    🚧 Subscription (CKQuerySubscription for cross-device push) — next PR
//    🚧 Background fetch handling — next PR
//
//  Why per-key records, not one file:
//  See docs/sync-architecture.md. Atomic per-key sync avoids the
//  binary-merge problem with iCloud Drive.
//

import CloudKit
import Combine
import Foundation

public final class CloudKitKeyringBackend: KeyringBackend {

    public let identifier = "rnp-cloudkit"
    public let displayName = "iCloud (CloudKit)"
    public var availability: BackendAvailability {
        CKContainer.default().accountStatus() == .available
            ? .available
            : .unavailable(reason: "Sign into iCloud to enable")
    }

    private let container: CKContainer
    private let db: CKDatabase
    private let subject = CurrentValueSubject<[KeyringKeyRecord], Never>([])
    private let recordType = "RNPKey"

    public init(container: CKContainer = .default()) {
        self.container = container
        self.db = container.privateCloudDatabase
    }

    // MARK: KeyringBackend

    public func load() throws -> [KeyringKeyRecord] {
        subject.value
    }

    public func upsert(_ record: KeyringKeyRecord) throws {
        let ckRecord = makeRecord(from: record)
        let op = CKModifyRecordsOperation(recordsToSave: [ckRecord], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.qualityOfService = .userInitiated
        op.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.reload()
            case .failure(let err):
                RnpLogger.keyring.error("CloudKit upsert failed: \(err.localizedDescription, privacy: .public)")
            }
        }
        db.add(op)
    }

    public func delete(fingerprint: String) throws {
        let id = CKRecord.ID(recordName: fingerprint)
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [id])
        op.qualityOfService = .userInitiated
        op.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success: self?.reload()
            case .failure(let err):
                RnpLogger.keyring.error("CloudKit delete failed: \(err.localizedDescription, privacy: .public)")
            }
        }
        db.add(op)
    }

    public func observeChanges(_ handler: @escaping ([KeyringKeyRecord]) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: handler)
    }

    // MARK: Pull path

    /// Queries CloudKit for all RNPKey records. Used by `load()` on
    /// startup. Subscription-based live updates are TODO (next PR).
    public func reload() {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let op = CKQueryOperation(query: query)
        var records: [KeyringKeyRecord] = []
        op.recordMatchedBlock = { _, result in
            if case .success(let ck) = result, let record = Self.record(from: ck) {
                records.append(record)
            }
        }
        op.queryResultBlock = { [weak self] _ in
            DispatchQueue.main.async {
                self?.subject.send(records)
            }
        }
        db.add(op)
    }

    // MARK: CKRecord ↔ KeyringKeyRecord

    private func makeRecord(from key: KeyringKeyRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: key.id)
        let record = CKRecord(recordType: recordType, recordID: id)
        record["primaryUserID"] = key.primaryUserID as CKRecordValue
        record["allUserIDs"] = key.allUserIDs as CKRecordValue
        record["keyBytes"] = key.keyBytes as CKRecordValue
        record["hasSecret"] = (key.hasSecret ? 1 : 0) as CKRecordValue
        record["keyCreationDate"] = key.keyCreationDate as CKRecordValue
        if let exp = key.keyExpirationDate {
            record["keyExpirationDate"] = exp as CKRecordValue
        }
        record["modifiedAt"] = key.modifiedAt as CKRecordValue
        record["modifiedBy"] = key.modifiedBy as CKRecordValue
        return record
    }

    private static func record(from ck: CKRecord) -> KeyringKeyRecord? {
        guard let id = ck["primaryUserID"] as? String,
              let keyBytes = ck["keyBytes"] as? Data,
              let modified = ck["modifiedAt"] as? Date else { return nil }
        return KeyringKeyRecord(
            id: ck.recordID.recordName,
            primaryUserID: id,
            allUserIDs: (ck["allUserIDs"] as? [String]) ?? [],
            keyBytes: keyBytes,
            hasSecret: (ck["hasSecret"] as? Int ?? 0) == 1,
            keyCreationDate: (ck["keyCreationDate"] as? Date) ?? Date(),
            keyExpirationDate: ck["keyExpirationDate"] as? Date,
            modifiedAt: modified,
            modifiedBy: (ck["modifiedBy"] as? String) ?? "cloud"
        )
    }
}

private extension CKContainer {
    /// Synchronous account-status check for the availability property.
    /// Wraps the async API in a semaphore — safe because availability
    /// is called infrequently and off the main queue.
    func accountStatus() -> CKAccountStatus {
        let semaphore = DispatchSemaphore(value: 0)
        var status: CKAccountStatus = .couldNotDetermine
        self.accountStatus { s, _ in
            status = s
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return status
    }
}
