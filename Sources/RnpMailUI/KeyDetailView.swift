//
//  KeyDetailView.swift
//  swift-rnp
//
//  Detail sheet for an OpenPGP key.
//

import AppKit
import SwiftUI
import MailSecurityEngine
import TrustStore

/// Actions available for a key in the detail sheet.
public struct KeyDetailActions {
    public var onExportPublic: () -> Void
    public var onExportSecret: () -> Void
    public var onDelete: () -> Void
    public var onExtendExpiry: () -> Void
    public var onRevoke: () -> Void
    public var onRotateEncryption: () -> Void
    public var onRotateSigning: () -> Void
    public var onPublish: () -> Void
    public var onMarkVerified: () -> Void

    public init(
        onExportPublic: @escaping () -> Void = {},
        onExportSecret: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onExtendExpiry: @escaping () -> Void = {},
        onRevoke: @escaping () -> Void = {},
        onRotateEncryption: @escaping () -> Void = {},
        onRotateSigning: @escaping () -> Void = {},
        onPublish: @escaping () -> Void = {},
        onMarkVerified: @escaping () -> Void = {}
    ) {
        self.onExportPublic = onExportPublic
        self.onExportSecret = onExportSecret
        self.onDelete = onDelete
        self.onExtendExpiry = onExtendExpiry
        self.onRevoke = onRevoke
        self.onRotateEncryption = onRotateEncryption
        self.onRotateSigning = onRotateSigning
        self.onPublish = onPublish
        self.onMarkVerified = onMarkVerified
    }
}

/// Detail sheet showing metadata and subkeys for a single OpenPGP key.
public struct KeyDetailView: View {
    public let key: KeyInfo
    public let subkeys: [SubkeyInfo]
    public let isRecipient: Bool
    public let trustState: TrustState
    public let actions: KeyDetailActions

    @State private var showDeleteConfirmation = false
    @State private var showSecretExportConfirmation = false
    @State private var showNotImplementedAlert = false
    @State private var notImplementedMessage = ""

    public init(
        key: KeyInfo,
        subkeys: [SubkeyInfo],
        isRecipient: Bool,
        trustState: TrustState = .unverified,
        actions: KeyDetailActions
    ) {
        self.key = key
        self.subkeys = subkeys
        self.isRecipient = isRecipient
        self.trustState = trustState
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
        .alert("detail.delete.title", isPresented: $showDeleteConfirmation) {
            Button("button.delete", role: .destructive) { actions.onDelete() }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("detail.delete.message")
        }
        .alert(
            "detail.exportSecret.title",
            isPresented: $showSecretExportConfirmation
        ) {
            Button("button.export", role: .destructive) { actions.onExportSecret() }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("detail.exportSecret.message")
        }
        .alert(
            "alert.comingSoon.title",
            isPresented: $showNotImplementedAlert
        ) {
            Button("button.ok") {}
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
                    Badge(text: "badge.revoked".localized, color: .red)
                } else if key.isExpired {
                    Badge(text: "badge.expired".localized, color: .red)
                } else if isRecipient {
                    Badge(text: trustBadgeText, color: trustBadgeColor)
                }
            }
        }
    }

    private var fingerprintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("detail.fingerprint")
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
                .help("detail.copyFingerprint.help")
                .accessibilityIdentifier("keydetail.copy-fingerprint")
                .accessibilityLabel("detail.copyFingerprint.help")
            }
        }
    }

    private var userIDsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("detail.userIDs")
                .font(.headline)
            ForEach(key.userIDs, id: \.self) { userID in
                Text(userID)
                    .textSelection(.enabled)
            }
        }
    }

    private var subkeysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "detail.subkeys.title".localized, subkeys.count))
                .font(.headline)
            Table(subkeys) {
                TableColumn("detail.subkeys.algorithm") { subkey in
                    Text(subkey.algorithmLabel)
                }
                TableColumn("detail.subkeys.created") { subkey in
                    Text(subkey.creationDate, style: .date)
                }
                TableColumn("detail.subkeys.expires") { subkey in
                    if let date = subkey.expirationDate {
                        Text(date, style: .date)
                    } else {
                        Text("detail.subkeys.never")
                    }
                }
                TableColumn("detail.subkeys.capabilities") { subkey in
                    Text(subkey.capabilities.joined(separator: ", ").capitalized)
                }
            }
            .frame(minHeight: 120)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("detail.actions.title")
                .font(.headline)
            HStack(spacing: 12) {
                Button("detail.exportPublic") { actions.onExportPublic() }
                    .accessibilityIdentifier("keydetail.export-public")
                Button("detail.exportSecret") { showSecretExportConfirmation = true }
                    .accessibilityIdentifier("keydetail.export-secret")
                Button("detail.deleteKey") { showDeleteConfirmation = true }
                    .accessibilityIdentifier("keydetail.delete")
                Button("detail.publish") { actions.onPublish() }
                    .accessibilityIdentifier("keydetail.publish")
            }
            HStack(spacing: 12) {
                Button("detail.extendExpiry") { actions.onExtendExpiry() }
                    .accessibilityIdentifier("keydetail.extend-expiry")
                Button("detail.revoke") { actions.onRevoke() }
                    .accessibilityIdentifier("keydetail.revoke")
            }
            HStack(spacing: 12) {
                Button("detail.rotateEncryption") { actions.onRotateEncryption() }
                    .accessibilityIdentifier("keydetail.rotate-encryption")
                Button("detail.rotateSigning") { actions.onRotateSigning() }
                    .accessibilityIdentifier("keydetail.rotate-signing")
            }
            if isRecipient && trustState != .verified {
                Button("detail.markVerified") { actions.onMarkVerified() }
                    .buttonStyle(.borderedProminent)
                    .tint(trustState == .problem ? .red : .orange)
                    .accessibilityIdentifier("keydetail.mark-verified")
            }
        }
    }

    private var trustBadgeText: String {
        switch trustState {
        case .verified:
            return "trust.verified".localized
        case .problem:
            return "trust.conflict".localized
        case .unverified:
            return "trust.unverified".localized
        }
    }

    private var trustBadgeColor: Color {
        switch trustState {
        case .verified:
            return .green
        case .problem:
            return .red
        case .unverified:
            return .orange
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
            isRecipient: true,
            trustState: .unverified,
            actions: KeyDetailActions()
        )
    }
}
#endif
