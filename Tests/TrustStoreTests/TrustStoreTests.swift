//
//  TrustStoreTests.swift
//  swift-rnp
//
//  Tests for the tamper-detecting TrustStore: state transitions, conflict
//  detection, persistence, and signature verification.
//

import CryptoKit
import XCTest
@testable import TrustStore

final class TrustStoreTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in tempDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirectories = []
    }

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-rnp-truststore-tests")
            .appendingPathComponent(UUID().uuidString)
        tempDirectories.append(url)
        return url
    }

    private func makeStore(directory: URL? = nil) throws -> TrustStore {
        try TrustStore(directory: directory ?? makeDirectory(), privateKey: Curve25519.Signing.PrivateKey())
    }

    // MARK: - State transitions

    func testUnknownFingerprintIsUnverified() throws {
        let store = try makeStore()
        XCTAssertEqual(store.state(forFpr: "AABBCCDD"), .unverified)
    }

    func testNoteSeenRecordsUnverifiedTOFU() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        XCTAssertEqual(store.state(forFpr: "FPR1"), .unverified)
        XCTAssertEqual(store.state(forEmail: "alice@example.com"), .unverified)
        XCTAssertTrue(store.conflicts().isEmpty)
    }

    func testMarkVerified() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.markVerified(fingerprint: "FPR1")
        XCTAssertEqual(store.state(forFpr: "FPR1"), .verified)
        XCTAssertEqual(store.state(forEmail: "alice@example.com"), .verified)
    }

    func testMarkProblem() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.markProblem(fingerprint: "FPR1")
        XCTAssertEqual(store.state(forFpr: "FPR1"), .problem)
    }

    // MARK: - Conflict detection

    func testDifferentFingerprintForSameEmailCreatesConflict() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR2")

        XCTAssertEqual(store.state(forEmail: "alice@example.com"), .problem)
        XCTAssertEqual(store.state(forFpr: "FPR2"), .problem)

        let conflicts = store.conflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.email, "alice@example.com")
        XCTAssertEqual(conflicts.first?.existingFingerprint, "FPR1")
        XCTAssertEqual(conflicts.first?.newFingerprint, "FPR2")
        XCTAssertTrue(store.hasConflict(forEmail: "alice@example.com"))
    }

    func testMarkVerifiedResolvesConflict() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR2")
        XCTAssertFalse(store.conflicts().isEmpty)

        try store.markVerified(fingerprint: "FPR2")
        XCTAssertTrue(store.conflicts().isEmpty)
        XCTAssertEqual(store.state(forFpr: "FPR2"), .verified)
        XCTAssertEqual(store.state(forEmail: "alice@example.com"), .verified)
    }

    func testResolveConflictAcceptsNewFingerprint() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR2")
        try store.resolveConflict(email: "alice@example.com", fingerprint: "FPR2")
        XCTAssertTrue(store.conflicts().isEmpty)
        XCTAssertEqual(store.state(forEmail: "alice@example.com"), .verified)
        XCTAssertEqual(store.state(forFpr: "FPR2"), .verified)
    }

    func testEmailIsNormalized() throws {
        let store = try makeStore()
        try store.noteSeen(email: "Alice@Example.COM", fingerprint: "FPR1")
        try store.noteSeen(email: "  alice@example.com  ", fingerprint: "FPR2")
        XCTAssertEqual(store.conflicts().count, 1)
        XCTAssertEqual(store.conflicts().first?.email, "alice@example.com")
    }

    // MARK: - Persistence and tamper detection

    func testPersistsAcrossInstances() throws {
        let directory = makeDirectory()
        let key = Curve25519.Signing.PrivateKey()
        let first = try TrustStore(directory: directory, privateKey: key)
        try first.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try first.markVerified(fingerprint: "FPR1")

        let second = try TrustStore(directory: directory, privateKey: key)
        XCTAssertEqual(second.state(forEmail: "alice@example.com"), .verified)
    }

    func testTamperedDatabaseResetsToEmpty() throws {
        let directory = makeDirectory()
        let key = Curve25519.Signing.PrivateKey()
        let store = try TrustStore(directory: directory, privateKey: key)
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.markVerified(fingerprint: "FPR1")

        let databaseURL = directory.appendingPathComponent(TrustStore.databaseFilename)
        var data = try XCTUnwrap(Data(contentsOf: databaseURL))
        data[10] ^= 0x01
        try data.write(to: databaseURL, options: .atomic)

        let reopened = try TrustStore(directory: directory, privateKey: key)
        XCTAssertEqual(reopened.state(forEmail: "alice@example.com"), .unverified)
        XCTAssertTrue(reopened.conflicts().isEmpty)
    }

    func testTamperedSignatureResetsToEmpty() throws {
        let directory = makeDirectory()
        let key = Curve25519.Signing.PrivateKey()
        let store = try TrustStore(directory: directory, privateKey: key)
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.markVerified(fingerprint: "FPR1")

        let signatureURL = directory.appendingPathComponent(TrustStore.signatureFilename)
        var signature = try XCTUnwrap(Data(contentsOf: signatureURL))
        signature[0] ^= 0x01
        try signature.write(to: signatureURL, options: .atomic)

        let reopened = try TrustStore(directory: directory, privateKey: key)
        XCTAssertEqual(reopened.state(forEmail: "alice@example.com"), .unverified)
        XCTAssertTrue(reopened.conflicts().isEmpty)
    }

    func testWrongKeyRejectsDatabase() throws {
        let directory = makeDirectory()
        let firstKey = Curve25519.Signing.PrivateKey()
        let store = try TrustStore(directory: directory, privateKey: firstKey)
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")
        try store.markVerified(fingerprint: "FPR1")

        let wrongKey = Curve25519.Signing.PrivateKey()
        let reopened = try TrustStore(directory: directory, privateKey: wrongKey)
        XCTAssertEqual(reopened.state(forEmail: "alice@example.com"), .unverified)
    }

    func testSchemaVersionIsPersisted() throws {
        let directory = makeDirectory()
        let store = try makeStore(directory: directory)
        try store.noteSeen(email: "alice@example.com", fingerprint: "FPR1")

        let databaseURL = directory.appendingPathComponent(TrustStore.databaseFilename)
        let data = try XCTUnwrap(Data(contentsOf: databaseURL))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
    }
}
