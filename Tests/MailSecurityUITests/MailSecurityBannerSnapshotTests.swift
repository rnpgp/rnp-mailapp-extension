//
//  MailSecurityBannerSnapshotTests.swift
//  swift-rnp
//
//  Structural and snapshot tests for the Mail security banner. Each test
//  verifies the banner's view hierarchy (labels, trust text, button) for one
//  signature/trust combination, and records a reference PNG for visual review.
//
//  The structural assertions are the primary check and are robust across
//  machines. The PNG comparison is a secondary visual check that records
//  references on first run and warns on mismatch (it does not fail, because
//  font rendering is machine-specific). To treat PNG mismatches as failures,
//  set the environment variable `SNAPSHOT_STRICT=1`.
//

import AppKit
import CryptoKit
import XCTest
import MailSecurityEngine
import Rnp
import TrustStore
@testable import MailSecurityUI

final class MailSecurityBannerSnapshotTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in tempDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirectories = []
    }

    // MARK: - Single signer: signature status × trust state

    func testSnapshot_valid_verified() throws {
        try snapshotSingleSigner(status: .valid, trust: .verified)
    }

    func testSnapshot_valid_unverified() throws {
        try snapshotSingleSigner(status: .valid, trust: .unverified)
    }

    func testSnapshot_valid_problem() throws {
        try snapshotSingleSigner(status: .valid, trust: .problem)
    }

    func testSnapshot_expired_verified() throws {
        try snapshotSingleSigner(status: .expired, trust: .verified)
    }

    func testSnapshot_expired_unverified() throws {
        try snapshotSingleSigner(status: .expired, trust: .unverified)
    }

    func testSnapshot_expired_problem() throws {
        try snapshotSingleSigner(status: .expired, trust: .problem)
    }

    func testSnapshot_invalid_verified() throws {
        try snapshotSingleSigner(status: .invalid, trust: .verified)
    }

    func testSnapshot_invalid_unverified() throws {
        try snapshotSingleSigner(status: .invalid, trust: .unverified)
    }

    func testSnapshot_invalid_problem() throws {
        try snapshotSingleSigner(status: .invalid, trust: .problem)
    }

    func testSnapshot_signerUnknown_verified() throws {
        try snapshotSingleSigner(status: .signerUnknown, trust: .verified)
    }

    func testSnapshot_signerUnknown_unverified() throws {
        try snapshotSingleSigner(status: .signerUnknown, trust: .unverified)
    }

    func testSnapshot_signerUnknown_problem() throws {
        try snapshotSingleSigner(status: .signerUnknown, trust: .problem)
    }

    func testSnapshot_unknown_verified() throws {
        try snapshotSingleSigner(status: .unknown, trust: .verified)
    }

    func testSnapshot_unknown_unverified() throws {
        try snapshotSingleSigner(status: .unknown, trust: .unverified)
    }

    func testSnapshot_unknown_problem() throws {
        try snapshotSingleSigner(status: .unknown, trust: .problem)
    }

    // MARK: - Unsigned message

    func testSnapshot_unsignedMessage() {
        let view = MailSecurityBannerView(signers: [], trustStore: nil)
        assertBannerStructure(
            view: view,
            expectedRows: [ExpectedRow(label: nil, trustLabel: nil, detail: "No valid signatures found on this message.", hasButton: false)]
        )
        assertSnapshot(named: "unsigned", view: view)
    }

    // MARK: - Multiple signers

    func testSnapshot_multipleSignersMixedStates() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        try store.markVerified(fingerprint: Self.fprAlice)
        try store.noteSeen(email: "bob@example.com", fingerprint: Self.fprBob)
        try store.noteSeen(email: "mallory@example.com", fingerprint: Self.fprMallory)

        let signers = [
            signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid),
            signer(label: "Bob <bob@example.com>", fpr: Self.fprBob, status: .valid),
            signer(label: "Mallory <mallory@example.com>", fpr: Self.fprMallory, status: .invalid),
        ]
        let view = MailSecurityBannerView(signers: signers, trustStore: store)

        let expected = signers.map { expectedRow(for: $0, trustStore: store) }
        assertBannerStructure(view: view, expectedRows: expected)
        assertSnapshot(named: "multiple-mixed-states", view: view)
    }

    func testSnapshot_multipleSignersAllVerified() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        try store.markVerified(fingerprint: Self.fprAlice)
        try store.noteSeen(email: "bob@example.com", fingerprint: Self.fprBob)
        try store.markVerified(fingerprint: Self.fprBob)

        let signers = [
            signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid),
            signer(label: "Bob <bob@example.com>", fpr: Self.fprBob, status: .valid),
        ]
        let view = MailSecurityBannerView(signers: signers, trustStore: store)

        let expected = signers.map { expectedRow(for: $0, trustStore: store) }
        assertBannerStructure(view: view, expectedRows: expected)
        assertSnapshot(named: "multiple-all-verified", view: view)
    }

    // MARK: - Trust store unavailable

    func testSnapshot_trustStoreUnavailable() {
        let view = MailSecurityBannerView(
            signers: [signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid)],
            trustStore: nil
        )
        assertBannerStructure(
            view: view,
            expectedRows: [ExpectedRow(label: "Alice <alice@example.com>", trustLabel: "Trust state unavailable", detail: "Trust information cannot be loaded while the keyring is unavailable.", hasButton: false)]
        )
        assertSnapshot(named: "trust-store-unavailable", view: view)
    }

    // MARK: - Behavior

    func testUnsignedMessageShowsPlaceholder() {
        let view = MailSecurityBannerView(signers: [], trustStore: nil)
        let labels = allSubviews(of: view).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains("No valid signatures found on this message."))
    }

    func testReviewDeepLinkButtonCarriesFingerprint() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        let view = MailSecurityBannerView(
            signers: [signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid)],
            trustStore: store
        )
        let buttons = allSubviews(of: view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first?.title, "Review in RnpMail")
        XCTAssertEqual(buttons.first?.identifier?.rawValue, Self.fprAlice)
    }

    func testNoReviewDeepLinkForVerifiedSigner() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        try store.markVerified(fingerprint: Self.fprAlice)
        let view = MailSecurityBannerView(
            signers: [signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid)],
            trustStore: store
        )
        let buttons = allSubviews(of: view).compactMap { $0 as? NSButton }
        XCTAssertTrue(buttons.isEmpty)
    }

    // MARK: - Helpers

    private static let fprAlice = "AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111"
    private static let fprBob = "BBBB2222BBBB2222BBBB2222BBBB2222BBBB2222"
    private static let fprMallory = "CCCC3333CCCC3333CCCC3333CCCC3333CCCC3333"

    private struct ExpectedRow {
        let label: String?
        let trustLabel: String?
        let detail: String
        let hasButton: Bool
    }

    private func snapshotSingleSigner(
        status: RnpSignatureStatus,
        trust: TrustState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        switch trust {
        case .unverified:
            break
        case .verified:
            try store.markVerified(fingerprint: Self.fprAlice)
        case .problem:
            try store.markProblem(fingerprint: Self.fprAlice)
        }
        let signer = signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: status)
        let view = MailSecurityBannerView(signers: [signer], trustStore: store)

        let expected = [expectedRow(for: signer, trustStore: store)]
        assertBannerStructure(view: view, expectedRows: expected, file: file, line: line)
        assertSnapshot(
            named: "single-\(status.rawValue)-\(trust.rawValue)",
            view: view,
            file: file,
            line: line
        )
    }

    private func signer(
        label: String,
        fpr: String,
        status: RnpSignatureStatus
    ) -> MailSecurityBannerView.Signer {
        MailSecurityBannerView.Signer(
            label: label,
            context: SignerContext(fingerprint: fpr, status: status.rawValue)
        )
    }

    private func expectedRow(
        for signer: MailSecurityBannerView.Signer,
        trustStore: TrustStore?
    ) -> ExpectedRow {
        let status = signer.context.flatMap { RnpSignatureStatus(rawValue: $0.status) } ?? .unknown
        let model: SignerTrustViewModel
        if let trustStore = trustStore {
            let trust: TrustState
            if let fingerprint = signer.context?.fingerprint {
                trust = trustStore.state(forFpr: fingerprint)
            } else {
                trust = .unverified
            }
            model = mapSignerTrust(status: status, trust: trust)
        } else {
            model = SignerTrustViewModel(
                label: "Trust state unavailable",
                detail: "Trust information cannot be loaded while the keyring is unavailable.",
                intent: .caution,
                reviewDeepLink: false
            )
        }
        return ExpectedRow(
            label: signer.label,
            trustLabel: model.label,
            detail: model.detail,
            hasButton: model.reviewDeepLink
        )
    }

    private func makeStore() throws -> TrustStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-rnp-mailsecurityui-tests")
            .appendingPathComponent(UUID().uuidString)
        tempDirectories.append(url)
        return try TrustStore(directory: url, privateKey: Curve25519.Signing.PrivateKey())
    }

    private var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("snapshots")
    }

    /// Verifies the banner's view hierarchy matches the expected rows.
    private func assertBannerStructure(
        view: MailSecurityBannerView,
        expectedRows: [ExpectedRow],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let textFields = allSubviews(of: view).compactMap { $0 as? NSTextField }
        let buttons = allSubviews(of: view).compactMap { $0 as? NSButton }

        let labels = textFields.map(\.stringValue)
        let buttonTitles = buttons.map(\.title)

        // The title is always present.
        XCTAssertTrue(labels.contains("OpenPGP signature"), "Missing banner title", file: file, line: line)

        for expected in expectedRows {
            if let label = expected.label {
                XCTAssertTrue(labels.contains(label), "Missing name label: \(label)", file: file, line: line)
            }
            if let trustLabel = expected.trustLabel {
                XCTAssertTrue(labels.contains(trustLabel), "Missing trust label: \(trustLabel)", file: file, line: line)
            }
            XCTAssertTrue(labels.contains(expected.detail), "Missing detail: \(expected.detail)", file: file, line: line)

            if expected.hasButton {
                XCTAssertTrue(buttonTitles.contains("Review in RnpMail"), "Missing review button", file: file, line: line)
            }
        }
    }

    /// Records the reference PNG when missing, otherwise compares against it.
    /// Mismatches warn but do not fail unless `SNAPSHOT_STRICT=1`.
    private func assertSnapshot(
        named name: String,
        view: MailSecurityBannerView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let data = pngData(for: view) else {
            XCTFail("Could not render banner to PNG", file: file, line: line)
            return
        }
        let referenceURL = snapshotDirectory.appendingPathComponent("\(name).png")
        guard let reference = try? Data(contentsOf: referenceURL) else {
            do {
                try FileManager.default.createDirectory(
                    at: snapshotDirectory,
                    withIntermediateDirectories: true
                )
                try data.write(to: referenceURL)
            } catch {
                XCTFail("Could not record snapshot \(name): \(error)", file: file, line: line)
            }
            return
        }
        guard data == reference else {
            let actualURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name)-actual.png")
            try? data.write(to: actualURL)
            let message = """
            Snapshot mismatch for \(name). Actual rendering written to \(actualURL.path). \
            This is a warning because font rendering is machine-specific. \
            To treat it as a failure, set SNAPSHOT_STRICT=1.
            """
            if ProcessInfo.processInfo.environment["SNAPSHOT_STRICT"] == "1" {
                XCTFail(message, file: file, line: line)
            } else {
                print("WARNING: \(message)")
            }
            return
        }
    }

    /// Renders the banner at its fitting size for a 360pt width.
    private func pngData(for view: MailSecurityBannerView) -> Data? {
        view.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        view.layoutSubtreeIfNeeded()
        let height = view.fittingSize.height
        view.frame = NSRect(x: 0, y: 0, width: 360, height: height)

        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderBack(nil)
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.orderOut(nil)
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }
}
