//
//  KeyDetailView.swift
//  swift-rnp
//
//  Detail sheet for an OpenPGP key.
//

import AppKit
import SwiftUI
import MailSecurityEngine

/// Actions available for a key in the detail sheet.
public struct KeyDetailActions {
    public var onExportPublic: () -> Void
    public var onExportSecret: () -> Void
    public var onDelete: () -> Void
    public var onExtendExpiry: () -> Void
    public var onRevoke: () -> Void

    public init(
        onExportPublic: @escaping () -> Void = {},
        onExportSecret: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onExtendExpiry: @escaping () -> Void = {},
        onRevoke: @escaping () -> Void = {}
    ) {
        self.onExportPublic = onExportPublic
        self.onExportSecret = onExportSecret
        self.onDelete = onDelete
        self.onExtendExpiry = onExtendExpiry
        self.onRevoke = onRevoke
    }
}

/// Detail sheet showing metadata and subkeys for a single OpenPGP key.
public struct KeyDetailView: View {
    public let key: KeyInfo
    public let subkeys: [SubkeyInfo]
    public let isRecipient: Bool
    public let actions: KeyDetailActions

    @State private var showDeleteConfirmation = false
    @State private var showSecretExportConfirmation = false
    @State private var showNotImplementedAlert = false
    @State private var notImplementedMessage = ""

    public init(
        key: KeyInfo,
        subkeys: [SubkeyInfo],
        isRecipient: Bool,
        actions: KeyDetailActions
    ) {
        self.key = key
        self.subkeys = subkeys
        self.isRecipient = isRecipient
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                fingerprintSection
                userIDsSection
                subkeysSection
                if !isRecipient {
                    actionsSection
                }
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .alert("Delete key?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { actions.onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the key from the shared keyring. This cannot be undone.")
        }
        .alert(
            "Export secret key?",
            isPresented: $showSecretExportConfirmation
        ) {
            Button("Export", role: .destructive) { actions.onExportSecret() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The secret key will be exported as an armored, passphrase-protected block. Keep it safe.")
        }
        .alert(
            "Coming soon",
            isPresented: $showNotImplementedAlert
        ) {
            Button("OK") {}
        } message: {
            Text(notImplementedMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key.primaryUserID)
                .font(.title2)
            HStack(spacing: 8) {
                Text(key.algorithmLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary, lineWidth: 1)
                    )
                if key.isRevoked {
                    Badge(text: "Revoked", color: .red)
                } else if key.isExpired {
                    Badge(text: "Expired", color: .red)
                } else if isRecipient {
                    Badge(text: "Unverified", color: .orange)
                }
            }
        }
    }

    private var fingerprintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fingerprint")
                .font(.headline)
            HStack(spacing: 8) {
                Text(key.fingerprint.groupedFingerprintFull)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    copyToClipboard(key.fingerprint)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy full fingerprint")
            }
        }
    }

    private var userIDsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("User IDs")
                .font(.headline)
            ForEach(key.userIDs, id: \.self) { userID in
                Text(userID)
                    .textSelection(.enabled)
            }
        }
    }

    private var subkeysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subkeys (\(subkeys.count))")
                .font(.headline)
            Table(subkeys) {
                TableColumn("Algorithm") { subkey in
                    Text(subkey.algorithmLabel)
                }
                TableColumn("Created") { subkey in
                    Text(subkey.creationDate, style: .date)
                }
                TableColumn("Expires") { subkey in
                    if let date = subkey.expirationDate {
                        Text(date, style: .date)
                    } else {
                        Text("Never")
                    }
                }
                TableColumn("Capabilities") { subkey in
                    Text(subkey.capabilities.joined(separator: ", ").capitalized)
                }
            }
            .frame(minHeight: 120)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)
            HStack(spacing: 12) {
                Button("Export public key") { actions.onExportPublic() }
                Button("Export secret key…") { showSecretExportConfirmation = true }
                Button("Delete key") { showDeleteConfirmation = true }
            }
            HStack(spacing: 12) {
                Button("Extend expiry") {
                    notImplementedMessage = "Not yet implemented — see task 05"
                    showNotImplementedAlert = true
                }
                Button("Revoke") {
                    notImplementedMessage = "Not yet implemented — see task 05"
                    showNotImplementedAlert = true
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 1)
            )
    }
}

private extension String {
    /// Groups a hex fingerprint into blocks of four characters.
    var groupedFingerprintFull: String {
        let cleaned = self
        return stride(from: 0, to: cleaned.count, by: 4)
            .map { offset -> String in
                let start = cleaned.index(cleaned.startIndex, offsetBy: offset)
                let end = cleaned.index(start, offsetBy: 4, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
                return String(cleaned[start ..< end])
            }
            .joined(separator: " ")
    }
}

#if DEBUG
struct KeyDetailView_Previews: PreviewProvider {
    static var previews: some View {
        KeyDetailView(
            key: KeyInfo(
                fingerprint: "ABCD1234EFGH5678IJKL9012MNOP3456QRST7890",
                primaryUserID: "Preview <preview@example.com>",
                userIDs: ["Preview <preview@example.com>"],
                hasSecret: true,
                algorithm: "RSA",
                bits: 3072,
                creationDate: Date(),
                expirationDate: Date().addingTimeInterval(86400 * 365),
                isRevoked: false,
                subkeyCount: 1
            ),
            subkeys: [],
            isRecipient: false,
            actions: KeyDetailActions()
        )
    }
}
#endif
