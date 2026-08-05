//
//  DeletionConfirmationState.swift
//  RNP
//
//  Three-step state machine for key deletion. Prevents misclicks
//  from destroying user data.
//
//  Flow:
//    .warning       → "Are you sure? [Continue] [Cancel]"
//    .typeToConfirm → "Type the fingerprint to confirm. [Continue] [Cancel]"
//    .finalWarning  → "A backup will be saved to <path>. Last chance.
//                      [Delete Forever] [Cancel]"
//    .done          → success state with backup summary
//
//  Single-key path requires typing the actual fingerprint (matches
//  Apple's pattern for deleting system files). Multi-key path
//  requires typing "DELETE" — listing all fingerprints would be
//  unreasonable.
//

import Foundation

@MainActor
public final class DeletionConfirmationState: ObservableObject {

    public enum Step: Equatable {
        case warning           // Step 1: "Are you sure?"
        case typeToConfirm     // Step 2: type fingerprint or "DELETE"
        case finalWarning      // Step 3: "Backup will be saved. Last chance."
        case working           // Encryption + write in progress
        case done(BackupSummary)  // Success — show backup path
        case failed(String)    // Backup or delete failed
    }

    @Published public var step: Step = .warning
    @Published public var typedConfirmation: String = ""
    @Published public var passphrase: String = ""
    @Published public var confirmPassword: String = ""
    @Published public var backupURL: URL?

    public let fingerprints: [String]
    public let primaryUserIDs: [String]
    private let defaultBackupLocation: URL

    public init(fingerprints: [String], primaryUserIDs: [String]) {
        self.fingerprints = fingerprints
        self.primaryUserIDs = primaryUserIDs
        self.defaultBackupLocation = KeyBackupArchive.defaultBackupDirectory
            .appendingPathComponent(KeyBackupArchive.suggestedFilename())
        self.backupURL = defaultBackupLocation
    }

    // MARK: Navigation

    public func advanceFromWarning() {
        guard case .warning = step else { return }
        step = .typeToConfirm
    }

    public func advanceFromTypeConfirm() {
        guard case .typeToConfirm = step else { return }
        guard isTypedConfirmationValid else { return }
        step = .finalWarning
    }

    public func back() {
        switch step {
        case .typeToConfirm: step = .warning
        case .finalWarning:  step = .typeToConfirm
        default: break
        }
    }

    public func reset() {
        step = .warning
        typedConfirmation = ""
        passphrase = ""
        confirmPassword = ""
        backupURL = defaultBackupLocation
    }

    // MARK: Validation

    /// True if the user typed what we asked for. Single key: the
    /// fingerprint (or its last 16 chars, since that's what users
    /// actually see). Multiple keys: the literal word "DELETE".
    public var isTypedConfirmationValid: Bool {
        let typed = typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        if fingerprints.count == 1 {
            let fpr = fingerprints[0]
            return typed.caseInsensitiveCompare(fpr) == .orderedSame
                || typed.caseInsensitiveCompare(String(fpr.suffix(16))) == .orderedSame
        }
        return typed == "DELETE"
    }

    /// True if the passphrase looks valid for the backup. We don't
    /// enforce complexity — the user is the one who'll need to
    /// remember it.
    public var isPassphraseValid: Bool {
        !passphrase.isEmpty && passphrase == confirmPassword
    }

    public var canProceedToDelete: Bool {
        isTypedConfirmationValid && isPassphraseValid && backupURL != nil
    }

    // MARK: Helpers for the UI

    public var expectedConfirmationText: String {
        if fingerprints.count == 1 {
            let fpr = fingerprints[0]
            return "Type the fingerprint: \(fpr) (or the last 16 chars: \(fpr.suffix(16)))"
        }
        return "Type DELETE in capital letters"
    }
}
