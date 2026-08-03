//
//  RnpMailAppError.swift
//  RNP
//
//  The single typed error enum for the app layer. Every user-visible
//  error path flows through this. Localization keys live next to the
//  cases so adding a case reminds you to add the string.
//
//  See TODO.complete/20-unified-errors.md and docs/adr/0002 (the
//  engine layer keeps its own MailSecurityError / RnpError types;
//  this enum is the app-layer translation).
//

import Foundation

public enum RnpMailAppError: Error, LocalizedError {
    // MARK: Keyring
    case keyringUnavailable
    case keyringLocked
    case keyringOpenFailed(underlying: String?)
    case keyNotFound(fingerprint: String)
    case recipientNotFound(fingerprint: String)
    case signingKeyNotFound(fingerprint: String)
    case noSigningKeyConfigured
    case noRecipients

    // MARK: File operations
    case encryptFailed(underlying: String?)
    case decryptFailed(underlying: String?)
    case signFailed(underlying: String?)
    case verifyFailed(underlying: String?)
    case readFailed(path: String)
    case writeFailed(path: String)
    case invalidPassphrase

    // MARK: Mail extension
    case mailExtensionNotEnabled
    case mailComposeCancelled

    // MARK: Backup / restore
    case backupFailed(underlying: String?)
    case restoreFailed(underlying: String?)

    // MARK: Engine passthrough
    case engine(Error)

    public var errorDescription: String? {
        switch self {
        // Keyring
        case .keyringUnavailable:
            return "error.keyringUnavailable".localized
        case .keyringLocked:
            return "error.keyringLocked".localized
        case .keyringOpenFailed(let reason):
            if let reason {
                return String(format: "error.keyringOpenFailed.withReason".localized, reason)
            }
            return "error.keyringOpenFailed".localized
        case .keyNotFound(let fpr):
            return String(format: "error.keyNotFound".localized, String(fpr.prefix(16)))
        case .recipientNotFound(let fpr):
            return String(format: "error.recipientNotFound".localized, String(fpr.prefix(16)))
        case .signingKeyNotFound(let fpr):
            return String(format: "error.signingKeyNotFound".localized, String(fpr.prefix(16)))
        case .noSigningKeyConfigured:
            return "error.noSigningKeyConfigured".localized
        case .noRecipients:
            return "error.noRecipients".localized

        // File operations
        case .encryptFailed(let reason):
            return reason.map { String(format: "error.encryptFailed.withReason".localized, $0) }
                ?? "error.encryptFailed".localized
        case .decryptFailed(let reason):
            return reason.map { String(format: "error.decryptFailed.withReason".localized, $0) }
                ?? "error.decryptFailed".localized
        case .signFailed(let reason):
            return reason.map { String(format: "error.signFailed.withReason".localized, $0) }
                ?? "error.signFailed".localized
        case .verifyFailed(let reason):
            return reason.map { String(format: "error.verifyFailed.withReason".localized, $0) }
                ?? "error.verifyFailed".localized
        case .readFailed(let path):
            return String(format: "error.readFailed".localized, path)
        case .writeFailed(let path):
            return String(format: "error.writeFailed".localized, path)
        case .invalidPassphrase:
            return "error.invalidPassphrase".localized

        // Mail
        case .mailExtensionNotEnabled:
            return "error.mailExtensionNotEnabled".localized
        case .mailComposeCancelled:
            return "error.mailComposeCancelled".localized

        // Backup / restore
        case .backupFailed(let reason):
            return reason.map { String(format: "error.backupFailed.withReason".localized, $0) }
                ?? "error.backupFailed".localized
        case .restoreFailed(let reason):
            return reason.map { String(format: "error.restoreFailed.withReason".localized, $0) }
                ?? "error.restoreFailed".localized

        // Engine passthrough — localize the underlying error directly
        case .engine(let err):
            return err.localizedDescription
        }
    }

    /// Wrap an arbitrary engine error into the `.engine` case. Idempotent:
    /// if the error is already an `RnpMailAppError`, return as-is so we
    /// don't nest.
    public static func wrap(_ error: Error) -> RnpMailAppError {
        if let app = error as? RnpMailAppError { return app }
        return .engine(error)
    }
}

extension RnpMailAppError {
    /// Convenience for log lines. Stable across localization.
    public var debugTag: String {
        switch self {
        case .keyringUnavailable:           return "keyring_unavailable"
        case .keyringLocked:                return "keyring_locked"
        case .keyringOpenFailed:            return "keyring_open_failed"
        case .keyNotFound:                  return "key_not_found"
        case .recipientNotFound:            return "recipient_not_found"
        case .signingKeyNotFound:           return "signing_key_not_found"
        case .noSigningKeyConfigured:       return "no_signing_key_configured"
        case .noRecipients:                 return "no_recipients"
        case .encryptFailed:                return "encrypt_failed"
        case .decryptFailed:                return "decrypt_failed"
        case .signFailed:                   return "sign_failed"
        case .verifyFailed:                 return "verify_failed"
        case .readFailed:                   return "read_failed"
        case .writeFailed:                  return "write_failed"
        case .invalidPassphrase:            return "invalid_passphrase"
        case .mailExtensionNotEnabled:      return "mail_ext_not_enabled"
        case .mailComposeCancelled:         return "mail_compose_cancelled"
        case .backupFailed:                 return "backup_failed"
        case .restoreFailed:                return "restore_failed"
        case .engine:                       return "engine"
        }
    }
}
