//
//  FileEncryptionIntents.swift
//  RNP
//
//  App Intents for encrypting/decrypting files from Shortcuts, Finder
//  Quick Actions, and Spotlight. No separate extension target needed —
//  these run in the main RNP app process and use the shared keyring.
//
//  After building, users can:
//  1. Open Shortcuts → New Shortcut → search "Encrypt File"
//  2. Assign it as a Finder Quick Action
//  3. Right-click any file → Quick Actions → Encrypt File
//

import AppIntents
import Foundation

// MARK: - Encrypt

/// Encrypt a file for recipients in your RNP keyring.
struct EncryptFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Encrypt File"
    static var description = IntentDescription("Encrypt a file with OpenPGP for people in your RNP keyring.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "File")
    var file: IntentFile

    @Parameter(title: "Recipients", description: "People whose public keys can decrypt the file.")
    var recipientFingerprints: [String]

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let plaintext = file.data
        let keysManager = KeysManager()
        let ciphertext = try keysManager.encryptFile(plaintext, for: recipientFingerprints)
        let originalName = file.filename
        let encrypted = IntentFile(data: ciphertext, filename: "\(originalName).pgp")
        return .result(value: encrypted)
    }
}

// MARK: - Decrypt

/// Decrypt an OpenPGP-encrypted file (.pgp / .gpg / .asc).
struct DecryptFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Decrypt File"
    static var description = IntentDescription("Decrypt an OpenPGP-encrypted file using your RNP keyring.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "File")
    var file: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let ciphertext = file.data
        let keysManager = KeysManager()
        let plaintext = try keysManager.decryptFile(ciphertext)
        let originalName = file.filename
        let stripped = originalName
            .replacingOccurrences(of: ".pgp", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".gpg", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".asc", with: "", options: .caseInsensitive)
        return .result(value: IntentFile(data: plaintext, filename: stripped))
    }
}

// MARK: - Sign

/// Sign a file with one of your secret keys. Output is an inline-armored
/// OpenPGP signature by default; flip `detached` for a `.sig` file.
struct SignFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Sign File"
    static var description = IntentDescription("Sign a file with one of your OpenPGP secret keys.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "File")
    var file: IntentFile

    @Parameter(title: "Signing Key", description: "Which of your secret keys to sign with.")
    var signingKey: RecipientEntity

    @Parameter(title: "Detached Signature", description: "If on, produces a .sig file alongside the original. If off, embeds the signature in a .pgp.", default: false)
    var detached: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let payload = file.data
        let manager = KeysManager()
        let signed = detached
            ? try manager.signFileDetached(payload, withKeyFingerprint: signingKey.id)
            : try manager.signFile(payload, withKeyFingerprint: signingKey.id)
        let originalName = file.filename
        let suffix = detached ? ".sig" : ".pgp"
        return .result(value: IntentFile(data: signed, filename: "\(originalName)\(suffix)"))
    }
}

// MARK: - Verify

/// Verify an OpenPGP signature. Inline-signed files (`.pgp` / `.asc`
/// with an embedded signature) verify directly; for detached `.sig`
/// files, also pass the original payload via the `payload` parameter.
struct VerifyFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Verify Signature"
    static var description = IntentDescription("Verify an OpenPGP signature on a file using your RNP keyring.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Signed File", description: "The .pgp / .asc / .sig file to verify.")
    var file: IntentFile

    @Parameter(title: "Original Payload", description: "For detached signatures only: the original file the .sig covers. Leave empty for inline-signed files.")
    var payload: IntentFile?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = KeysManager()
        let data = file.data
        if let payloadFile = payload {
            let v = try manager.verifyDetachedSignature(data, forPayload: payloadFile.data)
            return .result(dialog: dialog(for: v))
        }
        let result = try manager.verifyFile(data)
        let v = SignatureVerification(
            isValid: result.valid,
            signerFingerprint: nil,
            signerUserID: nil,
            signedAt: nil
        )
        return .result(dialog: dialog(for: v))
    }

    private func dialog(for v: SignatureVerification) -> IntentDialog {
        let signer = v.signerUserID ?? v.signerFingerprint ?? "Unknown signer"
        if v.isValid {
            return IntentDialog("\("intent.verifyFile.valid") \(signer)")
        } else {
            return IntentDialog("\("intent.verifyFile.invalid") \(signer)")
        }
    }
}

// MARK: - Dynamic recipient provider

/// Populates the recipient picker in Shortcuts with keys from the keyring.
struct RecipientEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "OpenPGP Key"
    static var defaultQuery = RecipientQuery()

    var id: String  // fingerprint
    var displayName: String  // primary user ID

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(String(id.prefix(16)))…")
    }
}

struct RecipientQuery: EntityQuery {
    func entities(for ids: [String]) async throws -> [RecipientEntity] {
        let keysManager = KeysManager()
        return keysManager.keys
            .filter { ids.contains($0.fingerprint) }
            .map { RecipientEntity(id: $0.fingerprint, displayName: $0.primaryUserID) }
    }

    func suggestedEntities() async throws -> [RecipientEntity] {
        let keysManager = KeysManager()
        return keysManager.keys.map {
            RecipientEntity(id: $0.fingerprint, displayName: $0.primaryUserID)
        }
    }
}

// MARK: - App shortcuts (appear in Spotlight, Shortcuts, share sheet)

struct RNPAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EncryptFileIntent(),
            phrases: ["Encrypt file with \(.applicationName)"],
            shortTitle: "Encrypt File",
            systemImageName: "lock.doc"
        )
        AppShortcut(
            intent: DecryptFileIntent(),
            phrases: ["Decrypt file with \(.applicationName)"],
            shortTitle: "Decrypt File",
            systemImageName: "lock.open.doc"
        )
        AppShortcut(
            intent: SignFileIntent(),
            phrases: ["Sign file with \(.applicationName)"],
            shortTitle: "Sign File",
            systemImageName: "signature"
        )
        AppShortcut(
            intent: VerifyFileIntent(),
            phrases: ["Verify signature with \(.applicationName)"],
            shortTitle: "Verify Signature",
            systemImageName: "checkmark.seal"
        )
    }
}
