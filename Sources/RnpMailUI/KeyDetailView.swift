//
//  KeyDetailView.swift
//  swift-rnp
//
//  Detail view for an OpenPGP key, shown in the container app's detail
//  column and (on macOS 12 or on demand) in a sheet.
//

import AppKit
import CoreImage
import SwiftUI
import MailSecurityEngine
import TrustStore

/// Actions available for a key in the detail view.
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

/// Detail view showing metadata and subkeys for a single OpenPGP key.
public struct KeyDetailView: View {
    public let key: KeyInfo
    public let subkeys: [SubkeyInfo]
    public let isRecipient: Bool
    public let trustState: TrustState
    public let actions: KeyDetailActions
    /// Prefix for the view's accessibility identifiers. The sheet uses the
    /// default `keydetail`; embedding contexts (e.g. the split-view detail
    /// column) pass a distinct prefix so identifiers stay unique when both
    /// presentations are on screen.
    public let identifierPrefix: String

    @State private var showDeleteConfirmation = false
    @State private var showSecretExportConfirmation = false
    @State private var showNotImplementedAlert = false
    @State private var notImplementedMessage = ""

    public init(
        key: KeyInfo,
        subkeys: [SubkeyInfo],
        isRecipient: Bool,
        trustState: TrustState = .unverified,
        actions: KeyDetailActions,
        identifierPrefix: String = "keydetail"
    ) {
        self.key = key
        self.subkeys = subkeys
        self.isRecipient = isRecipient
        self.trustState = trustState
        self.actions = actions
        self.identifierPrefix = identifierPrefix
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if isRecipient {
                    trustSection
                }
                fingerprintSection
                metadataSection
                userIDsSection
                subkeysSection
                if !isRecipient {
                    actionsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: key.hasSecret ? "key.fill" : "key")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    key.isRevoked || key.isExpired ? Color.secondary : Color.accentColor,
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(key.primaryUserID)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text(key.algorithmLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if key.isRevoked {
                        Badge(text: "badge.revoked".localized, color: .red)
                    } else if key.isExpired {
                        Badge(text: "badge.expired".localized, color: .red)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Trust

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("detail.trust.title")
                .font(.headline)
            HStack(spacing: 10) {
                Image(systemName: trustIconName)
                    .font(.title3)
                    .foregroundStyle(trustColor)
                    .accessibilityHidden(true)
                Text(trustBadgeText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(trustColor)
                    .accessibilityIdentifier("\(identifierPrefix).trust-badge")
                    .accessibilityValue(trustState.rawValue)
                Spacer()
                if trustState != .verified {
                    Button("detail.markVerified") { actions.onMarkVerified() }
                        .buttonStyle(.borderedProminent)
                        .tint(trustState == .problem ? .red : .orange)
                        .accessibilityIdentifier("\(identifierPrefix).mark-verified")
                }
            }
            .padding(12)
            .background(
                trustColor.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .animation(.default, value: trustState)
    }

    // MARK: - Fingerprint

    private var fingerprintSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("detail.fingerprint")
                .font(.headline)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(key.fingerprint.groupedFingerprintFull)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        copyToClipboard(key.fingerprint)
                    } label: {
                        Label("contextmenu.copyFingerprint", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("detail.copyFingerprint.help")
                    .accessibilityIdentifier("\(identifierPrefix).copy-fingerprint")
                    .accessibilityLabel("detail.copyFingerprint.help")
                }
                Spacer()
                if let qrCode = qrCodeImage {
                    VStack(spacing: 6) {
                        Image(nsImage: qrCode)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 96, height: 96)
                            .padding(6)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("detail.qrCode")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("detail.qrCode".localized)
                }
            }
        }
    }

    /// QR code for the `OPENPGP4FPR:<fingerprint>` URI, rendered via the
    /// system's CoreImage QR generator.
    private var qrCodeImage: NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data("OPENPGP4FPR:\(key.fingerprint)".utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let targetSize: CGFloat = 288
        let scale = targetSize / max(output.extent.width, output.extent.height)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("detail.metadata.title")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                metadataRow("detail.algorithm") {
                    Text(key.algorithmLabel)
                }
                metadataRow("table.type") {
                    Text(key.hasSecret ? "key.type.keyPair".localized : "key.type.publicOnly".localized)
                }
                metadataRow("detail.created") {
                    Text(key.creationDate, style: .date)
                }
                metadataRow("detail.expires") {
                    if let expiration = key.expirationDate {
                        Text(expiration, style: .date)
                    } else {
                        Text("detail.subkeys.never")
                    }
                }
            }
        }
    }

    private func metadataRow<Content: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            value()
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    // MARK: - User IDs

    private var userIDsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("detail.userIDs")
                .font(.headline)
            ForEach(key.userIDs, id: \.self) { userID in
                Text(userID)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Subkeys

    private var subkeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("detail.actions.title")
                .font(.headline)
            HStack(spacing: 12) {
                Button("detail.exportPublic") { actions.onExportPublic() }
                    .accessibilityIdentifier("\(identifierPrefix).export-public")
                Button("detail.exportSecret") { showSecretExportConfirmation = true }
                    .accessibilityIdentifier("\(identifierPrefix).export-secret")
                Button("detail.publish") { actions.onPublish() }
                    .accessibilityIdentifier("\(identifierPrefix).publish")
            }
            HStack(spacing: 12) {
                Button("detail.extendExpiry") { actions.onExtendExpiry() }
                    .accessibilityIdentifier("\(identifierPrefix).extend-expiry")
                Button("detail.rotateEncryption") { actions.onRotateEncryption() }
                    .accessibilityIdentifier("\(identifierPrefix).rotate-encryption")
                Button("detail.rotateSigning") { actions.onRotateSigning() }
                    .accessibilityIdentifier("\(identifierPrefix).rotate-signing")
            }
            HStack(spacing: 12) {
                Button("detail.revoke") { actions.onRevoke() }
                    .accessibilityIdentifier("\(identifierPrefix).revoke")
                Button("detail.deleteKey", role: .destructive) { showDeleteConfirmation = true }
                    .accessibilityIdentifier("\(identifierPrefix).delete")
            }
        }
    }

    // MARK: - Trust presentation

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

    private var trustColor: Color {
        switch trustState {
        case .verified:
            return .green
        case .problem:
            return .red
        case .unverified:
            return .orange
        }
    }

    private var trustIconName: String {
        switch trustState {
        case .verified:
            return "checkmark.shield.fill"
        case .problem:
            return "exclamationmark.shield.fill"
        case .unverified:
            return "questionmark.shield"
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
            .background(color.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.6), lineWidth: 1)
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
