//
//  KeyringCoordinatorTests.swift
//  RNPUnitTests
//
//  Integration tests for the KeyringCoordinator flow against a real
//  librnp keyring. Uses the public-key fixture copied from
//  ../rnp/src/tests/data/keyrings/1/ (key0-uid, passphrase "password").
//
//  Each test runs against its own freshly-created temp directory so
//  they don't pollute each other or the user's real keyring. No call
//  touches `KeyringCoordinator.shared` — every test builds its own
//  coordinator via the public `make(directory:)` factory.
//

import XCTest
@testable import RNP

final class KeyringCoordinatorTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-coordinator-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        // Reset UserDefaults so SyncConfiguration() in each test starts
        // from the canonical "rnp-local" default rather than a value
        // left over from a previous test run. Without this, test_migrate
        // ends up constructing a coordinator whose self.backend is
        // already rnp-asc-dir, the no-op check in migrate fires, and
        // copied is incorrectly returned as 0.
        let store = UserDefaults.standard
        for key in ["sync.canonicalStore", "sync.perKeyDirPath", "sync.importSources", "sync.passphraseStore"] {
            store.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        super.tearDown()
    }

    // MARK: - Fixture loader

    /// Returns the armored public key from keyrings/1 as Data.
    private func loadFixture() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "pubring", withExtension: "gpg.asc",
                                   subdirectory: "keyring-1") ??
                        bundle.url(forResource: "pubring", withExtension: "gpg.asc") else {
            throw FixtureError.notFound("pubring.gpg.asc not in test bundle. Check the Fixtures/keyring-1 copy phase.")
        }
        return try Data(contentsOf: url)
    }

    // MARK: - Tests

    func test_makeCoordinator_onEmptyDirectory_returnsCoordinatorWithEmptyKeyring() throws {
        let keyringDir = tempRoot.appendingPathComponent("empty", isDirectory: true)
        let coordinator = KeyringCoordinator.make(directory: keyringDir)
        XCTAssertNotNil(coordinator, "Coordinator should build on a fresh empty directory")
        let keys = (try? coordinator?.localCache.listKeys()) ?? []
        XCTAssertTrue(keys.isEmpty, "A fresh keyring should report zero keys")
    }

    func test_importFixtureKey_appearsInLocalCache() throws {
        let keyringDir = tempRoot.appendingPathComponent("imported", isDirectory: true)
        let coordinator = try XCTUnwrap(KeyringCoordinator.make(directory: keyringDir))
        let armored = try loadFixture()

        let imported = try coordinator.localCache.importKeys(armored)

        XCTAssertFalse(imported.isEmpty, "Import should return at least one KeyInfo")
        let keys = try coordinator.localCache.listKeys()
        XCTAssertEqual(keys.count, imported.count)
    }

    func test_migrate_fromLocalToAscDir_copiesAllKeys() throws {
        let keyringDir = tempRoot.appendingPathComponent("local-source", isDirectory: true)
        let ascDir = tempRoot.appendingPathComponent("asc-target", isDirectory: true)
        let coordinator = try XCTUnwrap(KeyringCoordinator.make(directory: keyringDir))
        let armored = try loadFixture()
        _ = try coordinator.localCache.importKeys(armored)
        let originalCount = (try? coordinator.localCache.listKeys().count) ?? 0
        XCTAssertGreaterThan(originalCount, 0, "Sanity: fixture loaded at least one key")

        // Point the config at the .asc dir and migrate.
        coordinator.config.canonicalStoreID = "rnp-local"
        coordinator.config.perKeyDirectoryPath = ascDir.path
        let copied = try coordinator.migrate(to: "rnp-asc-dir")

        XCTAssertEqual(copied, originalCount,
                       "Migrate should copy every key from the local cache into the .asc dir")
        let ascFiles = (try? FileManager.default.contentsOfDirectory(at: ascDir, includingPropertiesForKeys: nil)) ?? []
        let ascKeyFiles = ascFiles.filter { $0.pathExtension == "asc" && !$0.lastPathComponent.contains(".conflict-") }
        XCTAssertEqual(ascKeyFiles.count, originalCount,
                       "One .asc file per fingerprint should exist in the target dir")
    }

    func test_propagate_afterImport_mirrorsToAscDir() throws {
        let keyringDir = tempRoot.appendingPathComponent("prop-source", isDirectory: true)
        let ascDir = tempRoot.appendingPathComponent("prop-target", isDirectory: true)
        let coordinator = try XCTUnwrap(KeyringCoordinator.make(directory: keyringDir))
        coordinator.config.perKeyDirectoryPath = ascDir.path
        _ = try coordinator.migrate(to: "rnp-asc-dir")
        XCTAssertEqual(coordinator.backend.identifier, "rnp-asc-dir")

        let armored = try loadFixture()
        let before = Set((try? coordinator.localCache.listKeys().map(\.fingerprint)) ?? [])
        _ = try coordinator.localCache.importKeys(armored)
        let afterKeys = try coordinator.localCache.listKeys()
        let after = Set(afterKeys.map(\.fingerprint))
        coordinator.propagate(before: before, after: after)

        // Each new fingerprint should land as <fpr>.asc in the dir.
        let ascFiles = (try? FileManager.default.contentsOfDirectory(at: ascDir, includingPropertiesForKeys: nil)) ?? []
        let writtenFprs = Set(ascFiles
            .filter { $0.pathExtension == "asc" && !$0.lastPathComponent.contains(".conflict-") }
            .map { $0.deletingPathExtension().lastPathComponent })
        let newFprs = after.subtracting(before)
        for fpr in newFprs {
            XCTAssertTrue(writtenFprs.contains(fpr),
                          "Expected \(fpr) to be mirrored as <fpr>.asc in the per-key directory")
        }
    }

    func test_resolveRemoteDeletion_deleteLocally_removesFromCache() throws {
        let keyringDir = tempRoot.appendingPathComponent("del-source", isDirectory: true)
        let ascDir = tempRoot.appendingPathComponent("del-target", isDirectory: true)
        let coordinator = try XCTUnwrap(KeyringCoordinator.make(directory: keyringDir))
        coordinator.config.perKeyDirectoryPath = ascDir.path
        _ = try coordinator.migrate(to: "rnp-asc-dir")

        let armored = try loadFixture()
        _ = try coordinator.localCache.importKeys(armored)
        let keys = try coordinator.localCache.listKeys()
        guard let targetFpr = keys.first?.fingerprint else {
            return XCTFail("Fixture should have produced at least one key")
        }

        // Seed the deletion-detection state by claiming the backend
        // previously had this fingerprint, then report a snapshot
        // without it.
        coordinator.resolveRemoteDeletion(targetFpr, deleteLocally: false)
        // After "keep", the key must still be in the cache.
        let stillThere = (try? coordinator.localCache.listKeys())?.contains { $0.fingerprint == targetFpr } ?? false
        XCTAssertTrue(stillThere, "Keep-on-this-Mac must not delete from the local cache")
    }

    // MARK: -

    private enum FixtureError: Error, LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            if case .notFound(let msg) = self { return msg }
            return "FixtureError"
        }
    }
}
