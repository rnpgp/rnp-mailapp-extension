//
//  ContentViewModel.swift
//  Ribose container
//
//  UI state and actions for the key manager window.
//

import AppKit
import CryptoKit
import Foundation
import KeyLifecycle
import MailSecurityEngine
import RnpMailUI
import TrustStore

/// Which tab is selected in the key manager.
enum KeyTab: String, CaseIterable {
    case myKeys = "My Keys"
    case recipients = "Recipients"

    var localizedName: String {
        switch self {
        case .myKeys:
            return "tab.myKeys".localized
        case .recipients:
            return "tab.recipients".localized
        }
    }
}

final class ContentViewModel: ObservableObject {
    @Published var selection: KeyInfo.ID?
    @Published var showGenerateSheet = false
    @Published var showDeleteConfirmation = false
    @Published var showDetailSheet = false
    @Published var showOnboarding = false
    @Published var showClipboardImport = false
    @Published var showExtendExpirySheet = false
    @Published var showRevokeConfirmation = false
    @Published var showRotateSheet = false
    @Published var rotateMessage = ""
    @Published var showPublishSheet = false
    @Published var publishMessage = ""
    @Published var showFetchSheet = false
    @Published var fetchQuery = ""
    @Published var fetchedKey: FetchedKey?
    @Published var clipboardText = ""
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published private(set) var generateAlgorithm: KeyAlgorithm = .ed25519
    @Published var selectedTab: KeyTab = .myKeys
    @Published var revokeFingerprintInput = ""
    @Published var revokeReason = ""
    @Published var extendExpiryDate = Date().addingTimeInterval(365 * 24 * 60 * 60)
    @Published var pendingReviewFingerprint: String?

    let manager: KeysManager
    private var lastClipboardHash: String?

    init(manager: KeysManager) {

        self.manager = manager
    }

    /// Opens the key detail sheet for the given fingerprint, switching to the
    /// Recipients tab and selecting the matching key.
    func openReview(fingerprint: String) {
        pendingReviewFingerprint = fingerprint
        if let key = manager.keys.first(where: { $0.fingerprint.compare(fingerprint, options: .caseInsensitive) == .orderedSame }) {
            selectedTab = key.hasSecret ? .myKeys : .recipients
            selection = key.id
            showDetailSheet = true
            pendingReviewFingerprint = nil
        }
    }

    /// Trust state for a key in the current list.
    func trustState(for key: KeyInfo) -> TrustState {
        manager.trustState(forFpr: key.fingerprint)
    }

    /// All unresolved key-change conflicts.
    var trustConflicts: [TrustConflict] {
        manager.trustConflicts()
    }

    /// Marks the selected key as verified.
    func markSelectedVerified() {
        guard let key = selectedKey else { return }
        manager.markVerified(fingerprint: key.fingerprint)
        propagateError()
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
        // Launch arguments arrive as strings ("NO"), which `as? Bool` does
        // not bridge; `bool(forKey:)` parses them correctly, so only fall
        // back to the default when the key is absent entirely.
        get {
            guard UserDefaults.standard.object(forKey: "autoDetectClipboardImport") != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: "autoDetectClipboardImport")
        }
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
            errorMessage = "error.clipboardNoKey".localized
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
        panel.message = "import.filePanelMessage".localized
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
            errorMessage = "error.exportPublicFailed".localized
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
            errorMessage = "error.exportSecretFailed".localized
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

    // MARK: - Lifecycle

    func rotateEncryptionSubkey() {
        guard let key = selectedKey else { return }
        manager.rotateEncryptionSubkey(for: key)
        propagateError()
    }

    func rotateSigningSubkey() {
        guard let key = selectedKey else { return }
        manager.rotateSigningSubkey(for: key)
        propagateError()
    }

    func extendSelectedExpiry() {
        guard let key = selectedKey else { return }
        manager.extendExpiry(for: key, to: extendExpiryDate)
        propagateError()
    }

    func revokeSelected() {
        guard let key = selectedKey else { return }
        guard revokeFingerprintInput.compare(key.fingerprint, options: .caseInsensitive) == .orderedSame else {
            errorMessage = "error.fingerprintMismatch".localized
            return
        }
        manager.revoke(key, code: .noReason, reason: revokeReason)
        revokeFingerprintInput = ""
        revokeReason = ""
        propagateError()
    }

    func expiryReport() -> [KeyExpiryItem] {
        manager.expiryReport()
    }

    // MARK: - Keyserver

    func publishSelectedKey() {
        guard let key = selectedKey else { return }
        Task {
            let result = await manager.publish(key: key)
            await MainActor.run {
                switch result {
                case .success(let receipt):
                    publishMessage = receipt.message ?? "publish.success.fallback".localized
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func discoverKey() {
        let query = fetchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task {
            let result: Result<FetchedKey, KeyServerError>
            if query.contains("@") {
                result = await manager.discoverByEmail(query)
            } else {
                result = await manager.discoverByFingerprint(query)
            }
            await MainActor.run {
                switch result {
                case .success(let key):
                    fetchedKey = key
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    fetchedKey = nil
                }
            }
        }
    }

    func importFetchedKey() {
        guard let key = fetchedKey else { return }
        manager.importKeys(key.data)
        propagateError()
        showFetchSheet = false
        fetchQuery = ""
        fetchedKey = nil
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
            return "error.keyNotFoundAfterGeneration".localized
        case .keyringError(let message):
            return message
        }
    }
}
