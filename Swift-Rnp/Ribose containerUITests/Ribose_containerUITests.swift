//
//  Ribose_containerUITests.swift
//  Ribose containerUITests
//
//  UI tests for the RnpMail container app.
//

import AppKit
import XCTest

final class Ribose_containerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO", "-autoDetectClipboardImport", "NO"]
        app.launch()
        return app
    }

    private func dismissOnboardingIfPresent(_ app: XCUIApplication) {
        let doneButton = app.buttons["onboarding.done"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        }
    }

    func testOnboardingRenders() throws {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testGenerateKeyFlow() throws {
        let app = launchApp()

        // Navigate to generate key form if onboarding is shown.
        let generateButton = app.buttons["onboarding.generate"]
        if generateButton.waitForExistence(timeout: 2) {
            generateButton.tap()
        }

        // Fill in user ID and passphrase.
        let userIDField = app.textFields["contentview.generate.userid"]
        XCTAssertTrue(userIDField.waitForExistence(timeout: 2))
        userIDField.tap()
        userIDField.typeText("UI Test <uitest@example.com>")

        let passphraseField = app.secureTextFields["contentview.generate.passphrase"]
        if passphraseField.exists {
            passphraseField.tap()
            passphraseField.typeText("ui-test-passphrase")
        }

        let confirmField = app.secureTextFields["contentview.generate.confirmPassphrase"]
        if confirmField.exists {
            confirmField.tap()
            confirmField.typeText("ui-test-passphrase")
        }

        // Submit.
        let submitButton = app.buttons["contentview.generate.confirm"]
        if submitButton.exists {
            submitButton.tap()
        }

        // The key list should eventually show the new key.
        let keyRow = app.staticTexts["UI Test <uitest@example.com>"]
        XCTAssertTrue(keyRow.waitForExistence(timeout: 5))
    }

    func testAccessibilityAuditOnboarding() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("performAccessibilityAudit requires macOS 14")
        }
        let app = launchApp()
        try app.performAccessibilityAudit()
    }

    func testAccessibilityAuditKeyList() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("performAccessibilityAudit requires macOS 14")
        }
        let app = launchApp()
        dismissOnboardingIfPresent(app)
        try app.performAccessibilityAudit()
    }

    func testAccessibilityAuditGenerateForm() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("performAccessibilityAudit requires macOS 14")
        }
        let app = launchApp()
        dismissOnboardingIfPresent(app)

        let generateMenu = app.buttons["contentview.generate-menu"]
        if generateMenu.waitForExistence(timeout: 2) {
            generateMenu.tap()
            let ed25519 = app.buttons["contentview.generate-ed25519"]
            if ed25519.waitForExistence(timeout: 2) {
                ed25519.tap()
            }
        }
        try app.performAccessibilityAudit()
    }

    func testAccessibilityAuditImportForm() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("performAccessibilityAudit requires macOS 14")
        }
        let app = launchApp()
        dismissOnboardingIfPresent(app)

        let importMenu = app.buttons["contentview.import-menu"]
        if importMenu.waitForExistence(timeout: 2) {
            importMenu.tap()
            let importClipboard = app.buttons["contentview.import-clipboard"]
            if importClipboard.waitForExistence(timeout: 2) {
                importClipboard.tap()
            }
        }
        try app.performAccessibilityAudit()
    }

    func testAccessibilityAuditKeyDetail() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("performAccessibilityAudit requires macOS 14")
        }
        let app = launchApp()
        dismissOnboardingIfPresent(app)

        // Select the first key row if one exists.
        let firstRow = app.tables["keyslist.table"].tableRows.firstMatch
        if firstRow.waitForExistence(timeout: 2) {
            firstRow.tap()
            let detailsButton = app.buttons["contentview.details-button"]
            if detailsButton.waitForExistence(timeout: 2) {
                detailsButton.tap()
            }
        }
        try app.performAccessibilityAudit()
    }

    // MARK: - Import / trust UI tests
    //
    // These tests launch the app with `--uitest-keyring-dir` pointing at a
    // fresh temporary directory so every launch starts with an empty keyring
    // and trust store, independent of the real app-group keyring.

    /// Per-launch temporary keyring directories, removed in tearDown.
    private var temporaryKeyringDirs: [String] = []

    override func tearDownWithError() throws {
        for dir in temporaryKeyringDirs {
            try? FileManager.default.removeItem(atPath: dir)
        }
        temporaryKeyringDirs = []
    }

    /// Launches the app against an isolated, empty keyring.
    ///
    /// - Parameter pasteboardText: when given, placed on the general
    ///   pasteboard (after launch, so the clipboard auto-detect sheet that
    ///   fires on activation does not preempt the menu-driven import) so the
    ///   app's "From Clipboard" import can read it.
    private func launchIsolatedApp(pasteboardText: String? = nil) -> XCUIApplication {
        // The app runs sandboxed (it is signed with entitlements for the UI
        // test runner), so it can only write inside its container; arbitrary
        // /tmp keyring directories are denied and it would silently fall back
        // to the shared container keyring. Per-launch directories inside the
        // container tmp keep every test isolated from the others and from
        // the user's real keyring.
        let containerTmp = NSHomeDirectory()
            .appending("/Library/Containers/com.rnpgp.RnpMail/Data/tmp")
        try? FileManager.default.createDirectory(
            atPath: containerTmp,
            withIntermediateDirectories: true
        )
        let keyringDir = containerTmp.appending("/rnp-uitest-keyring-\(UUID().uuidString)")
        temporaryKeyringDirs.append(keyringDir)
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-keyring-dir", keyringDir,
            "-hasCompletedOnboarding", "YES",
            "-autoDetectClipboardImport", "NO",
        ]
        // On macOS `launch()` merely reactivates an already-running instance
        // and ignores the new launch arguments; make sure each test gets a
        // fresh process bound to its own keyring directory.
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
        }
        app.launch()
        if let pasteboardText {
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pasteboardText, forType: .string)
        }
        return app
    }

    /// Dismisses the clipboard auto-detect sheet if it is showing.
    private func dismissClipboardSheetIfPresent(_ app: XCUIApplication) {
        let cancel = app.buttons["contentview.clipboard.cancel"]
        if cancel.waitForExistence(timeout: 1) {
            cancel.tap()
        }
    }

    /// Opens the import menu and taps one of its items.
    private func tapImportMenuItem(_ app: XCUIApplication, identifier: String) {
        dismissClipboardSheetIfPresent(app)
        let importMenu = app.descendants(matching: .any)["contentview.import-menu"]
        XCTAssertTrue(importMenu.waitForExistence(timeout: 10), "import menu should exist")
        let item = app.descendants(matching: .any)[identifier]
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: item
        )
        // Dismissed SwiftUI menus linger in the accessibility tree with zero
        // frames; a plain `waitForExistence` can match such a stale item and
        // the tap then goes nowhere. Wait until the item is actually
        // hittable, retrying the whole open-menu step once (the first click
        // after launch may only activate the window).
        for _ in 1 ... 2 {
            importMenu.tap()
            if XCTWaiter.wait(for: [hittable], timeout: 5) == .completed {
                item.tap()
                return
            }
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTFail("\(identifier) menu item did not become hittable")
    }

    /// Switches the key list to the Recipients tab.
    private func selectRecipientsTab(_ app: XCUIApplication) {
        let segment = app.radioButtons["Recipients"]
        if segment.waitForExistence(timeout: 3) {
            segment.tap()
            return
        }
        // Fallback: click the right-hand segment of the picker control.
        let picker = app.descendants(matching: .any)["contentview.tab-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "tab picker should exist")
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
    }

    private func keyRow(_ app: XCUIApplication, fingerprint: String) -> XCUIElement {
        // SwiftUI concatenates nested accessibility identifiers, so the row's
        // identifier is `keyslist.row.<fpr>-keyslist.row.<fpr>`; match by
        // substring instead of exact equality.
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS %@", "keyslist.row.\(fingerprint)"))
            .firstMatch
    }

    /// Selects the table row for the given fingerprint.
    ///
    /// The row's content view carries a double-tap gesture, so tapping the
    /// content element itself does not select the row; tapping the outline
    /// row does.
    private func selectKeyRow(_ app: XCUIApplication, fingerprint: String) {
        let row = app.outlineRows
            .containing(NSPredicate(format: "identifier CONTAINS %@", "keyslist.row.\(fingerprint)"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "table row should exist")
        row.tap()
    }

    private func waitForValue(
        _ element: XCUIElement,
        value: String,
        timeout: TimeInterval,
        _ message: String
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func waitForNonExistence(
        _ element: XCUIElement,
        timeout: TimeInterval,
        _ message: String
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    func testImportKeyFromClipboard() throws {
        let app = launchIsolatedApp(pasteboardText: UITestFixtures.clipboardKey)

        tapImportMenuItem(app, identifier: "contentview.import-clipboard")
        selectRecipientsTab(app)

        let row = keyRow(app, fingerprint: UITestFixtures.clipboardFingerprint)
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "imported key should appear in the recipients list"
        )
        XCTAssertTrue(
            row.label.contains(UITestFixtures.clipboardUserID),
            "row label should contain the imported user ID, got: \(row.label)"
        )
    }

    func testImportKeyFromFile() throws {
        let keyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnp-uitest-import-\(UUID().uuidString).txt")
        try UITestFixtures.fileKey.write(to: keyFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: keyFileURL) }

        let app = launchIsolatedApp()

        tapImportMenuItem(app, identifier: "contentview.import-file")

        // The app presents a modal NSOpenPanel; drive it via the keyboard:
        // Cmd+Shift+G focuses the "Go to the folder" field.
        let openPanel = app.dialogs.firstMatch
        XCTAssertTrue(openPanel.waitForExistence(timeout: 10), "open panel should appear")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(keyFileURL.path)
        app.typeKey(.return, modifierFlags: [])
        // On some macOS versions the first Return only selects the file in
        // the panel browser; confirm explicitly if the panel is still open.
        if openPanel.waitForExistence(timeout: 1) {
            let openButton = openPanel.buttons["Open"]
            if openButton.waitForExistence(timeout: 2) {
                openButton.tap()
            }
        }

        selectRecipientsTab(app)
        let row = keyRow(app, fingerprint: UITestFixtures.fileFingerprint)
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "imported key should appear in the recipients list"
        )
        XCTAssertTrue(
            row.label.contains(UITestFixtures.fileUserID),
            "row label should contain the imported user ID, got: \(row.label)"
        )
    }

    func testTrustMarkAsVerified() throws {
        let app = launchIsolatedApp(pasteboardText: UITestFixtures.trustKey)

        tapImportMenuItem(app, identifier: "contentview.import-clipboard")
        selectRecipientsTab(app)
        selectKeyRow(app, fingerprint: UITestFixtures.trustFingerprint)

        let detailsButton = app.buttons["contentview.details-button"]
        XCTAssertTrue(detailsButton.waitForExistence(timeout: 5), "details button should exist")
        detailsButton.tap()

        let badge = app.staticTexts["keydetail.trust-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "trust badge should appear in key detail")
        XCTAssertEqual(
            badge.value as? String, "unverified",
            "freshly imported key should be unverified"
        )

        let markVerified = app.buttons["keydetail.mark-verified"]
        XCTAssertTrue(markVerified.waitForExistence(timeout: 5), "Mark as verified button should appear")
        markVerified.tap()

        waitForValue(badge, value: "verified", timeout: 10, "badge should switch to verified")
    }

    func testTrustConflictAndResolution() throws {
        let app = launchIsolatedApp(pasteboardText: UITestFixtures.conflictKey1)
        tapImportMenuItem(app, identifier: "contentview.import-clipboard")

        // A second, different key for the same email address triggers a
        // key-change conflict in the trust store.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UITestFixtures.conflictKey2, forType: .string)
        tapImportMenuItem(app, identifier: "contentview.import-clipboard")

        let banner = app.descendants(matching: .any)["contentview.trust-conflict-banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 10),
            "trust-conflict banner should appear after importing a second key for the same address"
        )

        // Resolve the conflict by verifying the new key in its detail view.
        selectRecipientsTab(app)
        selectKeyRow(app, fingerprint: UITestFixtures.conflictFingerprint2)

        let detailsButton = app.buttons["contentview.details-button"]
        XCTAssertTrue(detailsButton.waitForExistence(timeout: 5), "details button should exist")
        detailsButton.tap()

        let badge = app.staticTexts["keydetail.trust-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "trust badge should appear in key detail")
        XCTAssertEqual(
            badge.value as? String, "problem",
            "conflicting key should start in problem state"
        )

        let markVerified = app.buttons["keydetail.mark-verified"]
        XCTAssertTrue(markVerified.waitForExistence(timeout: 5), "Mark as verified button should appear")
        markVerified.tap()

        waitForValue(badge, value: "verified", timeout: 10, "badge should switch to verified")

        // Encryption to an address is blocked while the trust store holds an
        // unresolved conflict for it; once the new fingerprint is verified
        // the conflict is removed, the banner disappears and encryption can
        // proceed.
        app.typeKey(.escape, modifierFlags: [])
        waitForNonExistence(
            banner, timeout: 10,
            "trust-conflict banner should disappear after the conflict is resolved"
        )
    }
}

// MARK: - Test key fixtures

/// Armored public keys generated with `gpg --quick-generate-key "<uid>" ed25519 sign never`.
/// Fingerprints are the uppercase hex form returned by `rnp_key_get_fprint`.
private enum UITestFixtures {
    static let clipboardUserID = "UITest Clipboard <uitest-clipboard@example.com>"
    static let clipboardFingerprint = "74E2A1E008CB1B1021192AA05225D37282795A2F"
    static let clipboardKey = """
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEal86iBYJKwYBBAHaRw8BAQdATr45ZRNywPi/pR3UT6pImaihhlFR3np8FxjC
yGCxwSa0L1VJVGVzdCBDbGlwYm9hcmQgPHVpdGVzdC1jbGlwYm9hcmRAZXhhbXBs
ZS5jb20+iK8EExYKAFcWIQR04qHgCMsbECEZKqBSJdNygnlaLwUCal86iBsUgAAA
AAAEAA5tYW51MiwyLjUrMS4xMiwwLDMCGwMFCwkIBwICIgIGFQoJCAsCBBYCAwEC
HgcCF4AACgkQUiXTcoJ5Wi9TzQD9H4Sb7C4nCKyabn0cMIrdyaat+BZ245WiU4ka
VwAiNEYBANeeX8kpKmf7PcCT9SAicHbZobTUpS5GxSrAgHjnbmMN
=sPB9
-----END PGP PUBLIC KEY BLOCK-----
"""

    static let fileUserID = "UITest File <uitest-file@example.com>"
    static let fileFingerprint = "1E3B6B50E143C2ED6B5D2989DB3FA5F0BDAC8FA8"
    static let fileKey = """
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEal86nhYJKwYBBAHaRw8BAQdAjiNwukrBju9TtPN5Ge+qyXcUAVBcl/g9LFsN
mw4AU0W0JVVJVGVzdCBGaWxlIDx1aXRlc3QtZmlsZUBleGFtcGxlLmNvbT6IrwQT
FgoAVxYhBB47a1DhQ8Lta10pids/pfC9rI+oBQJqXzqeGxSAAAAAAAQADm1hbnUy
LDIuNSsxLjEyLDAsMwIbAwULCQgHAgIiAgYVCgkICwIEFgIDAQIeBwIXgAAKCRDb
P6XwvayPqHmZAP9Qrv1f99HUWfJ8ajVqiF+pp9huLiFaEqpks0WIfNYGjAD/ZC6v
wT9RiUbxG6tU1zJouFQ8R+ma3T3Gsy3CG0wB8wE=
=hZ12
-----END PGP PUBLIC KEY BLOCK-----
"""

    static let trustUserID = "UITest Trust <uitest-trust@example.com>"
    static let trustFingerprint = "1DB2526CA45209432E30D89D89E52DE34923881C"
    static let trustKey = """
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEal86nhYJKwYBBAHaRw8BAQdA+0NoV0dRjfWJWmeWw9KQFHqkBMgMBj0KGlhV
uZ7un9e0J1VJVGVzdCBUcnVzdCA8dWl0ZXN0LXRydXN0QGV4YW1wbGUuY29tPoiv
BBMWCgBXFiEEHbJSbKRSCUMuMNidieUt40kjiBwFAmpfOp4bFIAAAAAABAAObWFu
dTIsMi41KzEuMTIsMCwzAhsDBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJ
EInlLeNJI4gc0jEA/08kvz3AdupT/y8+pnF3fIUB15wX63OjaFc5UcOxkGC5AQCl
MeoZ2tWP6zisJKqfBWhh3MsNB5kT7alpM0om9w3jCw==
=iDXN
-----END PGP PUBLIC KEY BLOCK-----
"""

    /// Two different keys for the same address, used by the conflict test.
    static let conflictUserID1 = "UITest Conflict <uitest-conflict@example.com>"
    static let conflictFingerprint1 = "AC0D1452E21AA855FC31CF4DD67088C3AC35900D"
    static let conflictKey1 = """
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEal86nhYJKwYBBAHaRw8BAQdA0ehkEc08CtYSJWhD8ZDbS9jD2+mE7HUUhPhn
knDd7Ve0LVVJVGVzdCBDb25mbGljdCA8dWl0ZXN0LWNvbmZsaWN0QGV4YW1wbGUu
Y29tPoivBBMWCgBXFiEErA0UUuIaqFX8Mc9N1nCIw6w1kA0FAmpfOp4bFIAAAAAA
BAAObWFudTIsMi41KzEuMTIsMCwzAhsDBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4H
AheAAAoJENZwiMOsNZANfrMBAK51v0qBjNv8pKWNSJ6LWJlUM9vJDwY4VwbpCH++
BgVTAP49IZSWJLi5DktHYAo60WvH5eDkVlyDhRKh/LHvB94sDA==
=zoMA
-----END PGP PUBLIC KEY BLOCK-----
"""

    static let conflictUserID2 = "UITest Conflict Two <uitest-conflict@example.com>"
    static let conflictFingerprint2 = "932CD90917C0070C331FDE908837B1DBCE319F46"
    static let conflictKey2 = """
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEal86txYJKwYBBAHaRw8BAQdAA5vpFLbGKyPI8qrXX9bJY8/83KW5iX6n8s2P
z1Bj6c60MVVJVGVzdCBDb25mbGljdCBUd28gPHVpdGVzdC1jb25mbGljdEBleGFt
cGxlLmNvbT6IrwQTFgoAVxYhBJMs2QkXwAcMMx/ekIg3sdvOMZ9GBQJqXzq3GxSA
AAAAAAQADm1hbnUyLDIuNSsxLjEyLDAsMwIbAwULCQgHAgIiAgYVCgkICwIEFgID
AQIeBwIXgAAKCRCIN7HbzjGfRjV4AP4+yvCcEidyJvL7tyrIcXRqyBM9VFAwtoXn
de4Dh6UfQgD/eC7FbyXSx0COEzGdjBl2x0CLROoqCdLqlb8fwi5hHAk=
=kHI8
-----END PGP PUBLIC KEY BLOCK-----
"""
}
