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
        let userIDField = app.textFields["generate.userID"]
        XCTAssertTrue(userIDField.waitForExistence(timeout: 2))
        userIDField.tap()
        userIDField.typeText("UI Test <uitest@example.com>")

        let passphraseField = app.secureTextFields["generate.passphrase"]
        if passphraseField.exists {
            passphraseField.tap()
            passphraseField.typeText("ui-test-passphrase")
        }

        let confirmField = app.secureTextFields["generate.confirmPassphrase"]
        if confirmField.exists {
            confirmField.tap()
            confirmField.typeText("ui-test-passphrase")
        }

        // Submit.
        let submitButton = app.buttons["generate.submit"]
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
        // Dismiss onboarding if present.
        let doneButton = app.buttons["onboarding.done"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        }
        try app.performAccessibilityAudit()
    }
}
