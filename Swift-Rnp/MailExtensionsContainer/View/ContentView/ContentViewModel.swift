//
//  ContentViewModel.swift
//  Ribose container
//
//  UI state and actions for the key manager window.
//

import AppKit
import CryptoKit
import Foundation
import MailSecurityEngine
import RnpMailUI

/// Which tab is selected in the key manager.
enum KeyTab: String, CaseIterable {
    case myKeys = "My Keys"
    case recipients = "Recipients"
}

final class ContentViewModel: ObservableObject {
    @Published var selection: KeyInfo.ID?
    @Published var showGenerateSheet = false
    @Published var showDeleteConfirmation = false
    @Published var showDetailSheet = false
    @Published var showOnboarding = false
    @Published var showClipboardImport = false
    @Published var clipboardText = ""
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published private(set) var generateAlgorithm: KeyAlgorithm = .ed25519
    @Published var selectedTab: KeyTab = .myKeys

    let manager: KeysManager
    private var lastClipboardHash: String?

    init(manager: KeysManager) {

        self.manager = manager
    }

    /// Keys visible in the current tab.
    var keys: [KeyInfo] {
        switch selectedTab {
        case .myKeys:
            return manager.keys.filter { $0.hasSecret }
        case .recipients:
            return manager.keys.filter { !$0.hasSecret }
        }
    }

    var selectedKey: KeyInfo? {
        keys.first { $0.id == selection }
    }

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var autoDetectClipboard: Bool {
        get { UserDefaults.standard.object(forKey: "autoDetectClipboardImport") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoDetectClipboardImport") }
    }

    /// Called on launch to decide whether to show onboarding.
    func checkOnboarding() {
        if !hasOnboarded && manager.keys.isEmpty {
            showOnboarding = true
        }
    }

    /// Manually reopen the onboarding flow from the Help menu.
    func reopenOnboarding() {
        showOnboarding = true
    }

    func markOnboardingComplete() {
        hasOnboarded = true
        showOnboarding = false
    }

    // MARK: - Generate

    func beginGenerate(algorithm: KeyAlgorithm) {
        generateAlgorithm = algorithm
        showGenerateSheet = true
    }

    func generate(userID: String, algorithm: KeyAlgorithm) {
        manager.generate(userID: userID, algorithm: algorithm)
        propagateError()
        propagateWarning()
    }

    /// Generates a key from the onboarding request and returns the result.
    func generateForOnboarding(
        userID: String,
        algorithm: KeyAlgorithm,
        passphrase: String,
        expirationSeconds: UInt32,
        useTouchID: Bool
    ) -> Result<OnboardingGenerationResult, Error> {
        manager.generate(
            userID: userID,
            algorithm: algorithm,
            passphrase: passphrase,
            expirationSeconds: expirationSeconds,
            useTouchID: useTouchID
        )
        propagateWarning()
        if let error = manager.lastError {
            manager.lastError = nil
            return .failure(OnboardingAppError.keyringError(error))
        }
        guard let key = manager.keys.first(where: { $0.primaryUserID == userID }) else {
            return .failure(OnboardingAppError.keyNotFoundAfterGeneration)
        }
        let revocationURL = manager.lastRevocationCertificateURL
            ?? AppGroup.keyringDirectory()
                .appendingPathComponent("\(key.fingerprint)-revocation.asc")
        return .success(OnboardingGenerationResult(
            userID: userID,
            fingerprint: key.fingerprint,
            revocationCertificateURL: revocationURL
        ))
    }

    /// Imports keys from the onboarding paste and returns the imported keys.
    func importForOnboarding(_ data: Data) -> Result<[KeyInfo], Error> {
        let imported = manager.importKeys(data)
        if let error = manager.lastError {
            manager.lastError = nil
            return .failure(OnboardingAppError.keyringError(error))
        }
        return .success(imported)
    }

    // MARK: - Import

    /// Imports armored key data from the general pasteboard.
    func importFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              text.contains("BEGIN PGP")
        else {
            errorMessage = "The clipboard does not contain an armored OpenPGP key."
            return
        }
        importKeys(Data(text.utf8))
    }

    /// Imports keys from dropped file URLs or raw data.
    func importData(_ data: Data) {
        importKeys(data)
    }

    /// Imports keys from a user-selected key file.
    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data, .text]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an OpenPGP key file to import"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                DispatchQueue.main.async {
                    self.importKeys(data)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Checks the pasteboard on app activation and offers to import a PGP block.
    func checkClipboardForPGP() {
        guard autoDetectClipboard,
              let text = NSPasteboard.general.string(forType: .string),
              text.contains("BEGIN PGP")
        else {
            return
        }
        let hash = Self.clipboardHash(text)
        guard hash != lastClipboardHash else { return }
        lastClipboardHash = hash
        clipboardText = text
        showClipboardImport = true
    }

    private static func clipboardHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    func confirmClipboardImport() {
        importKeys(Data(clipboardText.utf8))
        showClipboardImport = false
        clipboardText = ""
    }

    private func importKeys(_ data: Data) {
        manager.importKeys(data)
        propagateError()
    }

    // MARK: - Export

    /// Copies the armored public key of the current selection to the
    /// general pasteboard.
    func exportSelectedPublicToPasteboard() {
        guard let key = selectedKey else {
            return
        }
        guard let armored = manager.exportKey(fingerprint: key.fingerprint) else {
            errorMessage = "The key could not be exported."
            return
        }
        copyToPasteboard(String(decoding: armored, as: UTF8.self))
    }

    /// Copies the armored secret key of the current selection to the
    /// general pasteboard.
    func exportSelectedSecretToPasteboard() {
        guard let key = selectedKey else {
            return
        }
        guard let armored = manager.exportSecretKey(fingerprint: key.fingerprint) else {
            errorMessage = "The secret key could not be exported."
            return
        }
        copyToPasteboard(String(decoding: armored, as: UTF8.self))
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Delete

    func deleteSelected() {
        guard let key = selectedKey else {
            return
        }
        manager.delete(key)
        selection = nil
        propagateError()
    }

    // MARK: - Error / warning propagation

    private func propagateError() {
        errorMessage = manager.lastError
        manager.lastError = nil
    }

    private func propagateWarning() {
        if let warning = manager.lastWarning {
            warningMessage = warning.message
            manager.lastWarning = nil
        }
    }
}

enum OnboardingAppError: Error, LocalizedError {
    case keyNotFoundAfterGeneration
    case keyringError(String)

    var errorDescription: String? {
        switch self {
        case .keyNotFoundAfterGeneration:
            return "The key was generated but could not be found in the keyring."
        case .keyringError(let message):
            return message
        }
    }
}
