//
//  ContentViewModel.swift
//  RNP
//
//  UI state and actions for the key manager window.
//

import AppKit
import Combine
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
    @Published var currentSheet: Sheet?
    @Published var showDeleteConfirmation = false
    @Published var showOnboarding = false
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published private(set) var generateAlgorithm: KeyAlgorithm = .ed25519
    @Published var selectedTab: KeyTab = .myKeys
    @Published var revokeFingerprintInput = ""
    @Published var revokeReason = ""
    @Published var extendExpiryDate = Date().addingTimeInterval(365 * 24 * 60 * 60)
    @Published var pendingReviewFingerprint: String?
    /// Trust history sheet state.
    @Published private(set) var trustHistoryEmail = ""
    @Published private(set) var trustHistoryRecords: [TrustRecord] = []
    /// Whether a keyserver discovery (fetch sheet) is in flight.
    @Published var isDiscoveringKey = false
    /// Whether a keyserver publish is in flight.
    @Published var isPublishing = false
    /// Publish progress / result message, updated during the operation.
    @Published var publishMessage = ""
    /// Sidebar search query; filters the visible key list.
    @Published var searchText = ""
    /// Import failure shown as an inline banner in the sidebar (instead of a
    /// modal alert) so the user can fix the data and retry.
    @Published var importError: String?
    /// Fetch-sheet form state.
    @Published var fetchQuery = ""
    @Published var fetchedKey: FetchedKey?
    /// Clipboard-import sheet pending text.
    @Published var clipboardText = ""
    /// Drives the post-onboarding Mail extension setup sheet. Distinct from
    /// `currentSheet` because it isn't a tool-triggered sheet.
    @Published var showMailExtensionSetup = false

    let manager: KeysManager
    private var lastClipboardHash: String?
    private var managerObserver: AnyCancellable?

    init(manager: KeysManager) {

        self.manager = manager
        // Forward keyring changes so every view bound to this model (list,
        // banners, detail pane) re-renders — and animates — on mutation.
        managerObserver = manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Opens the key detail sheet for the given fingerprint, switching to the
    /// Recipients tab and selecting the matching key.
    func openReview(fingerprint: String) {
        pendingReviewFingerprint = fingerprint
        if let key = manager.keys.first(where: { $0.fingerprint.compare(fingerprint, options: .caseInsensitive) == .orderedSame }) {
            selectedTab = key.hasSecret ? .myKeys : .recipients
            selection = key.id
            currentSheet = .detail
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

    // MARK: - Trust conflicts and history

    /// Rejects the new key of the given conflict, keeping the old binding.
    func rejectConflict(_ conflict: TrustConflict) {
        manager.rejectConflict(email: conflict.email, newFingerprint: conflict.newFingerprint)
        propagateError()
    }

    /// Whether the key is the newly seen key of an unresolved conflict.
    func hasPendingKeyChange(for key: KeyInfo) -> Bool {
        manager.trustConflict(forNewFingerprint: key.fingerprint) != nil
    }

    /// Rejects this key as the new binding for its address, keeping the old
    /// binding (used by the key detail view's "Keep old binding" action).
    func rejectKeyChange(for key: KeyInfo) {
        guard let conflict = manager.trustConflict(forNewFingerprint: key.fingerprint) else {
            return
        }
        manager.rejectConflict(email: conflict.email, newFingerprint: conflict.newFingerprint)
        propagateError()
    }

    /// Opens the trust history sheet for the key's address.
    func openTrustHistory(for key: KeyInfo) {
        guard let email = manager.primaryEmail(for: key) else {
            return
        }
        trustHistoryEmail = email
        trustHistoryRecords = manager.trustHistory(forEmail: email)
        currentSheet = .trustHistory
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

    /// Keys shown in the sidebar: the current tab filtered by the search
    /// query (matched against user IDs and the fingerprint).
    var filteredKeys: [KeyInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return keys }
        return keys.filter { key in
            key.fingerprint.range(of: query, options: .caseInsensitive) != nil
                || key.userIDs.contains { $0.range(of: query, options: .caseInsensitive) != nil }
        }
    }

    /// Whether the sidebar search is active and matched nothing.
    var isSearchEmpty: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty && filteredKeys.isEmpty
    }

    var selectedKey: KeyInfo? {
        keys.first { $0.id == selection }
    }

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the user has confirmed in the in-app UI that they enabled
    /// "Mail" for RNP for Mail in System Settings → Extensions. Drives the
    /// Tools hub banner. The flag is advisory (we can't query Mail's
    /// permission directly); it just hides a banner the user has dismissed.
    var mailExtensionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "mailExtensionEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "mailExtensionEnabled") }
    }

    /// Whether the user has seen the Mail extension setup flow at least
    /// once. Gates auto-presenting the sheet after onboarding so we don't
    /// nag users who already skipped.
    var hasShownMailExtensionSetup: Bool {
        get { UserDefaults.standard.bool(forKey: "hasShownMailExtensionSetup") }
        set { UserDefaults.standard.set(newValue, forKey: "hasShownMailExtensionSetup") }
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

    /// Whether the Mail extension fetches missing recipient keys from
    /// keyservers while composing. Stored in the app-group defaults so the
    /// extension process reads the same value.
    var autoFetchRecipientKeys: Bool {
        get { RecipientKeyAutoFetch.isEnabled() }
        set {
            RecipientKeyAutoFetch.setEnabled(newValue)
            objectWillChange.send()
        }
    }

    /// Whether each sign/encrypt/decrypt operation requires user
    /// verification (Touch ID, with the login-password fallback), re-armed
    /// after the session timeout. Stored in the app-group defaults so the
    /// extension process reads the same value.
    var requireTouchIDPerOperation: Bool {
        get { OperationVerification.isEnabled() }
        set {
            OperationVerification.setEnabled(newValue)
            objectWillChange.send()
        }
    }

    /// How long a successful verification authorizes secret-key operations,
    /// in seconds.
    var operationVerificationTimeout: TimeInterval {
        get { OperationVerification.sessionTimeout() }
        set {
            OperationVerification.setSessionTimeout(newValue)
            objectWillChange.send()
        }
    }

    /// Called on launch to decide whether to show onboarding. Safe to
    /// call before `manager.bootstrap()` completes — it'll see an empty
    /// key list and treat the user as new. The subsequent
    /// `manager.$keys` combine listener below will re-evaluate once
    /// bootstrap finishes and surface the Mail extension setup sheet if
    /// the user turns out to be returning.
    func checkOnboarding() {
        if !hasOnboarded && manager.keys.isEmpty {
            showOnboarding = true
            return
        }
        if !hasShownMailExtensionSetup && !mailExtensionEnabled {
            showMailExtensionSetup = true
        }
    }

    /// Manually reopen the onboarding flow from the Help menu.
    func reopenOnboarding() {
        showOnboarding = true
    }

    func markOnboardingComplete() {
        hasOnboarded = true
        showOnboarding = false
        if !hasShownMailExtensionSetup {
            showMailExtensionSetup = true
        }
    }

    /// User confirmed Mail is granted permission in System Settings.
    func markMailExtensionEnabled() {
        mailExtensionEnabled = true
        hasShownMailExtensionSetup = true
        showMailExtensionSetup = false
        objectWillChange.send()
    }

    /// User dismissed the setup sheet without confirming (skip for now).
    func skipMailExtensionSetup() {
        hasShownMailExtensionSetup = true
        showMailExtensionSetup = false
    }

    /// Reopen the Mail extension setup sheet (called from the Tools hub
    /// banner).
    func reopenMailExtensionSetup() {
        showMailExtensionSetup = true
    }

    // MARK: - Keyring unlock (Touch ID)

    /// Whether the keyring is currently locked behind Touch ID.
    var keyringLocked: Bool {
        manager.keyringLocked
    }

    /// Attempts to unlock the keyring with Touch ID (system prompt).
    func unlockKeyringWithTouchID() {
        manager.unlockKeyring()
        propagateError()
    }

    /// Manual fallback: verifies the entered passphrase and unlocks this
    /// process. Returns `true` when accepted.
    func unlockKeyringManually(_ passphrase: String) -> Bool {
        let accepted = manager.unlockKeyringManually(passphrase: passphrase)
        propagateError()
        return accepted
    }

    // MARK: - Generate

    func beginGenerate(algorithm: KeyAlgorithm) {
        generateAlgorithm = algorithm
        currentSheet = .generate
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

    /// The imported secret key currently waiting for its foreign passphrase,
    /// driving the unlock prompt sheet. `nil` when no key is pending.
    var foreignPassphraseRequest: LockedSecretKeyInfo? {
        manager.foreignPassphraseRequests.first
    }

    /// Unlocks the pending key with `passphrase`, either storing it in the
    /// Keychain as the key's per-key passphrase or re-protecting the key
    /// with the keyring passphrase.
    ///
    /// - Returns: `true` when the key was unlocked; `false` when the
    ///   passphrase was wrong (the prompt stays open).
    func resolveForeignPassphrase(
        _ request: LockedSecretKeyInfo,
        passphrase: String,
        reprotectWithKeyringPassphrase: Bool
    ) -> Bool {
        let succeeded = reprotectWithKeyringPassphrase
            ? manager.reprotectForeignKey(passphrase, for: request)
            : manager.storeForeignPassphrase(passphrase, for: request)
        propagateError()
        return succeeded
    }

    /// Dismisses the pending unlock prompt without unlocking the key.
    func skipForeignPassphrase(_ request: LockedSecretKeyInfo) {
        manager.skipForeignPassphrase(for: request)
    }

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
        currentSheet = .clipboardImport
    }

    private static func clipboardHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    func confirmClipboardImport() {
        importKeys(Data(clipboardText.utf8))
        currentSheet = nil
        clipboardText = ""
    }

    private func importKeys(_ data: Data) {
        manager.importKeys(data)
        if let error = manager.lastError {
            importError = error
            manager.lastError = nil
        } else {
            importError = nil
        }
    }

    // MARK: - Export

    /// Reloads the key list from the keyring (toolbar refresh action).
    func refresh() {
        manager.reload()
    }

    /// Copies the key's fingerprint to the general pasteboard.
    func copyFingerprint(_ key: KeyInfo) {
        copyToPasteboard(key.fingerprint)
    }

    /// Copies the armored public key of the current selection to the
    /// general pasteboard.
    func exportSelectedPublicToPasteboard() {
        guard let key = selectedKey else {
            return
        }
        exportPublicToPasteboard(key)
    }

    /// Copies the armored public key of the given key to the general
    /// pasteboard.
    func exportPublicToPasteboard(_ key: KeyInfo) {
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

    /// Selects the given key and presents the delete confirmation (used by
    /// the list's context menu, where the clicked row may not be selected).
    func confirmDelete(_ key: KeyInfo) {
        selection = key.id
        showDeleteConfirmation = true
    }

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
        currentSheet = nil
        propagateError()
    }

    func rotateSigningSubkey() {
        guard let key = selectedKey else { return }
        manager.rotateSigningSubkey(for: key)
        currentSheet = nil
        propagateError()
    }

    func extendSelectedExpiry() {
        guard let key = selectedKey else { return }
        manager.extendExpiry(for: key, to: extendExpiryDate)
        currentSheet = nil
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
        currentSheet = nil
        propagateError()
    }

    func expiryReport() -> [KeyExpiryItem] {
        manager.expiryReport()
    }

    // MARK: - Keyserver

    func publishSelectedKey() {
        guard let key = selectedKey else { return }
        isPublishing = true
        Task {
            let result = await manager.publish(key: key)
            await MainActor.run {
                isPublishing = false
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
        isDiscoveringKey = true
        Task {
            let result: Result<FetchedKey, KeyServerError>
            if query.contains("@") {
                result = await manager.discoverByEmail(query)
            } else {
                result = await manager.discoverByFingerprint(query)
            }
            await MainActor.run {
                isDiscoveringKey = false
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
        importKeys(key.data)
        currentSheet = nil
        fetchQuery = ""
        fetchedKey = nil
    }

    /// Opens the fetch sheet pre-filled with an email address and starts the
    /// keyserver search. Used by the `rnpmail://fetch/<email>` deep link,
    /// e.g. from the Mail compose missing-key hint.
    func openFetch(email: String) {
        selectedTab = .recipients
        fetchQuery = email
        fetchedKey = nil
        currentSheet = .fetch
        discoverKey()
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
