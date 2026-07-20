//
//  Ribose_containerUITests.swift
//  Ribose containerUITests
//
//  UI tests for the RnpMail container app.
//

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
        let firstRow = app.tables["keyslist.table"].rows.firstMatch
        if firstRow.waitForExistence(timeout: 2) {
            firstRow.tap()
            let detailsButton = app.buttons["contentview.details-button"]
            if detailsButton.waitForExistence(timeout: 2) {
                detailsButton.tap()
            }
        }
        try app.performAccessibilityAudit()
    }
}
