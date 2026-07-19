//
//  KeyLifecycleTests.swift
//  swift-rnp
//
//  Tests for key lifecycle operations: subkey rotation, expiry extension,
//  revocation, and expiry reporting.
//

import XCTest
@testable import KeyLifecycle
import MailSecurityEngine
import Rnp

final class KeyLifecycleTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in tempDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirectories = []
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-rnp-keylifecycle-tests")
            .appendingPathComponent(UUID().uuidString)
        tempDirectories.append(url)
        return url
    }

    private func makeKeyManager(directory: URL? = nil) throws -> KeyManager {
        try KeyManager(directory: directory ?? makeTempDirectory(), password: "test-password")
    }

    // MARK: - Rotation

    func testRotateEncryptionSubkeyForRSA() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        let info = try manager.generateKey(userID: "Alice <alice@example.com>", algorithm: .rsa)
        let subkeysBefore = try manager.subkeys(for: info.fingerprint)
        XCTAssertEqual(subkeysBefore.count, 1)

        let summary = try lifecycle.rotateEncryptionSubkey(for: info.fingerprint)
        XCTAssertEqual(summary.primaryFingerprint, info.fingerprint)
        XCTAssertFalse(summary.newSubkeyFingerprint.isEmpty)
        XCTAssertEqual(summary.retiredSubkeyFingerprint, subkeysBefore.first?.fingerprint)

        let subkeysAfter = try manager.subkeys(for: info.fingerprint)
        XCTAssertEqual(subkeysAfter.count, 2)
    }

    func testRotateEncryptionSubkeyForEd25519() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        let info = try manager.generateKey(userID: "Bob <bob@example.com>", algorithm: .ed25519)
        let subkeysBefore = try manager.subkeys(for: info.fingerprint)
        XCTAssertEqual(subkeysBefore.count, 1)

        let summary = try lifecycle.rotateEncryptionSubkey(for: info.fingerprint)
        XCTAssertEqual(summary.primaryFingerprint, info.fingerprint)
        XCTAssertFalse(summary.newSubkeyFingerprint.isEmpty)

        let subkeysAfter = try manager.subkeys(for: info.fingerprint)
        XCTAssertEqual(subkeysAfter.count, 2)
    }

    func testOldEncryptionSubkeyGetsGraceExpiry() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        let info = try manager.generateKey(userID: "Alice <alice@example.com>", algorithm: .rsa)
        let oldSubkey = try XCTUnwrap(try manager.subkeys(for: info.fingerprint).first)

        _ = try lifecycle.rotateEncryptionSubkey(for: info.fingerprint)

        let updatedOldSubkey = try manager.subkeys(for: info.fingerprint)
            .first { $0.fingerprint == oldSubkey.fingerprint }
        XCTAssertNotNil(updatedOldSubkey)
        XCTAssertNotNil(updatedOldSubkey?.expirationDate)
        if let expiry = updatedOldSubkey?.expirationDate {
            let grace = Date().addingTimeInterval(TimeInterval(KeyLifecycleConfiguration.rotationGraceSeconds))
            let diff = abs(expiry.timeIntervalSince(grace))
            XCTAssertLessThan(diff, 10, "grace expiry should be ~30 days")
        }
    }

    // MARK: - Expiry extension

    func testExtendExpiry() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        let info = try manager.generateKey(
            userID: "Alice <alice@example.com>",
            algorithm: .ecdsa,
            expirationSeconds: 365 * 24 * 60 * 60
        )

        let newDate = Date().addingTimeInterval(2 * 365 * 24 * 60 * 60)
        try lifecycle.extendExpiry(for: info.fingerprint, newDate: newDate)

        let keys = try manager.listKeys()
        let updated = try XCTUnwrap(keys.first { $0.fingerprint == info.fingerprint })
        XCTAssertNotNil(updated.expirationDate)
        if let expiry = updated.expirationDate {
            let diff = abs(expiry.timeIntervalSince(newDate))
            XCTAssertLessThan(diff, 10)
        }
    }

    func testExtendExpiryRejectsPastDate() {
        do {
            let manager = try makeKeyManager()
            let lifecycle = KeyLifecycle(keyManager: manager)
            let info = try manager.generateKey(userID: "Alice <alice@example.com>", algorithm: .ecdsa)
            try lifecycle.extendExpiry(for: info.fingerprint, newDate: Date().addingTimeInterval(-86400))
            XCTFail("expected invalid expiry date error")
        } catch let error as KeyLifecycleError {
            XCTAssertEqual(error, .invalidExpiryDate)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Revocation

    func testRevokeKeyProducesCertificate() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        let info = try manager.generateKey(userID: "Alice <alice@example.com>", algorithm: .rsa)
        let certificate = try lifecycle.revoke(for: info.fingerprint, code: .superseded, reason: "Lost key")

        let armored = String(decoding: certificate, as: UTF8.self)
        XCTAssertTrue(armored.contains("BEGIN PGP"))

        let keys = try manager.listKeys()
        let revoked = try XCTUnwrap(keys.first { $0.fingerprint == info.fingerprint })
        XCTAssertTrue(revoked.isRevoked)
    }

    // MARK: - Expiry report

    func testExpiryReportIncludesExpiringKey() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        let info = try manager.generateKey(
            userID: "Alice <alice@example.com>",
            algorithm: .ed25519,
            expirationSeconds: 30 * 24 * 60 * 60 // 30 days
        )

        XCTAssertNotNil(info.expirationDate, "generated key should have an expiration date")
        let report = try lifecycle.expiryReport()
        XCTAssertTrue(report.contains { $0.fingerprint == info.fingerprint })
    }

    func testExpiryReportOmitsLongLivedKey() throws {
        let manager = try makeKeyManager()
        let lifecycle = KeyLifecycle(keyManager: manager)

        _ = try manager.generateKey(
            userID: "Alice <alice@example.com>",
            algorithm: .ecdsa,
            expirationSeconds: 365 * 24 * 60 * 60 // 1 year
        )

        let report = try lifecycle.expiryReport()
        XCTAssertTrue(report.isEmpty)
    }
}
