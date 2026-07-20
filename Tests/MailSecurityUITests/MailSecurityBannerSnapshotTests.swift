//
//  MailSecurityBannerSnapshotTests.swift
//  swift-rnp
//
//  Snapshot tests for the Mail security banner. Each test renders
//  `MailSecurityBannerView` for one signature/trust combination and compares
//  the PNG against a reference image in `Tests/Fixtures/snapshots/`.
//
//  When no reference image exists the test records one and passes. When the
//  banner UI intentionally changes, delete the affected reference PNGs and
//  re-run the tests to re-record them, then review the new images before
//  committing.
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
        assertSnapshot(named: "unsigned", view: view)
    }

    // MARK: - Multiple signers

    func testSnapshot_multipleSignersMixedStates() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        try store.markVerified(fingerprint: Self.fprAlice)
        try store.noteSeen(email: "bob@example.com", fingerprint: Self.fprBob)
        try store.noteSeen(email: "mallory@example.com", fingerprint: Self.fprMallory)

        let view = MailSecurityBannerView(
            signers: [
                signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid),
                signer(label: "Bob <bob@example.com>", fpr: Self.fprBob, status: .valid),
                signer(label: "Mallory <mallory@example.com>", fpr: Self.fprMallory, status: .invalid),
            ],
            trustStore: store
        )
        assertSnapshot(named: "multiple-mixed-states", view: view)
    }

    func testSnapshot_multipleSignersAllVerified() throws {
        let store = try makeStore()
        try store.noteSeen(email: "alice@example.com", fingerprint: Self.fprAlice)
        try store.markVerified(fingerprint: Self.fprAlice)
        try store.noteSeen(email: "bob@example.com", fingerprint: Self.fprBob)
        try store.markVerified(fingerprint: Self.fprBob)

        let view = MailSecurityBannerView(
            signers: [
                signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid),
                signer(label: "Bob <bob@example.com>", fpr: Self.fprBob, status: .valid),
            ],
            trustStore: store
        )
        assertSnapshot(named: "multiple-all-verified", view: view)
    }

    // MARK: - Trust store unavailable

    func testSnapshot_trustStoreUnavailable() {
        let view = MailSecurityBannerView(
            signers: [signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: .valid)],
            trustStore: nil
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
        let view = MailSecurityBannerView(
            signers: [signer(label: "Alice <alice@example.com>", fpr: Self.fprAlice, status: status)],
            trustStore: store
        )
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

    private func makeStore() throws -> TrustStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-rnp-mailsecurityui-tests")
            .appendingPathComponent(UUID().uuidString)
        tempDirectories.append(url)
        return try TrustStore(directory: url, privateKey: Curve25519.Signing.PrivateKey())
    }

    private var snapshotDirectory: URL {
        // Tests/MailSecurityUITests/MailSecurityBannerSnapshotTests.swift
        //   -> Tests/Fixtures/snapshots
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("snapshots")
    }

    /// Records the reference PNG when missing, otherwise compares against it.
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
            XCTFail(
                """
                Snapshot mismatch for \(name). Actual rendering written to \(actualURL.path). \
                If the UI change is intentional, delete Tests/Fixtures/snapshots/\(name).png \
                and re-run the tests to re-record it.
                """,
                file: file,
                line: line
            )
            return
        }
    }

    /// Renders the banner at its fitting size for a 360pt width.
    ///
    /// The view is hosted in a (background) window while rendering: the
    /// inline-bezel deep-link button only draws when its view hierarchy is
    /// backed by a real window, and `cacheDisplay` on a windowless hierarchy
    /// produces a blank image.
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
