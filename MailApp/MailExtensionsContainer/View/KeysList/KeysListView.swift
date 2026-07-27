//
//  KeysListView.swift
//  RNP
//
//  Table of the OpenPGP keys in the shared keyring.
//

import MailSecurityEngine
import RnpMailUI
import SwiftUI
import TrustStore

struct KeysListView: View {
    let keys: [KeyInfo]
    @Binding var selection: KeyInfo.ID?
    /// Trust state for a key, or `nil` when no trust indicator applies
    /// (e.g. the user's own key pairs).
    var trustState: ((KeyInfo) -> TrustState?)?
    var onDoubleTap: ((KeyInfo) -> Void)?
    var onExport: ((KeyInfo) -> Void)?
    var onCopyFingerprint: ((KeyInfo) -> Void)?
    var onDelete: ((KeyInfo) -> Void)?
    var onRefresh: (() -> Void)?

    init(
        keys: [KeyInfo],
        selection: Binding<KeyInfo.ID?>,
        trustState: ((KeyInfo) -> TrustState?)? = nil,
        onDoubleTap: ((KeyInfo) -> Void)? = nil,
        onExport: ((KeyInfo) -> Void)? = nil,
        onCopyFingerprint: ((KeyInfo) -> Void)? = nil,
        onDelete: ((KeyInfo) -> Void)? = nil,
        onRefresh: (() -> Void)? = nil
    ) {
        self.keys = keys
        self._selection = selection
        self.trustState = trustState
        self.onDoubleTap = onDoubleTap
        self.onExport = onExport
        self.onCopyFingerprint = onCopyFingerprint
        self.onDelete = onDelete
        self.onRefresh = onRefresh
    }

    var body: some View {
        Table(keys, selection: $selection) {
            TableColumn("table.userID") { key in
                HStack(spacing: RnpSpacing.sm - 2) {
                    RnpKeyAvatar(
                        hasSecret: key.hasSecret,
                        isDimmed: key.isRevoked || key.isExpired,
                        size: 28
                    )
                    VStack(alignment: .leading, spacing: RnpSpacing.xxs - 2) {
                        HStack(spacing: RnpSpacing.xxs + 2) {
                            Text(key.primaryUserID)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if let state = trustState?(key) {
                                TrustIndicator(state: state)
                            }
                        }
                        HStack(spacing: RnpSpacing.xxs + 2) {
                            Text(key.algorithmLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if key.isRevoked {
                                RnpBadge(text: "badge.revoked".localized, color: RnpBrand.critical)
                            } else if key.isExpired {
                                RnpBadge(text: "badge.expired".localized, color: RnpBrand.critical)
                            } else if let days = key.daysUntilExpiry, days < 60 {
                                RnpBadge(text: String(format: "badge.expiresIn".localized, days), color: RnpBrand.unverified)
                            }
                        }
                    }
                }
                .padding(.vertical, RnpSpacing.xxs - 2)
                // `onTapGesture` would consume the mouse events and prevent
                // the Table's own row selection; a simultaneous gesture lets
                // both the selection and the double-tap action fire.
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { onDoubleTap?(key) }
                )
                .contextMenu { contextMenu(for: key) }
                .help(key.fingerprint)
                .accessibilityIdentifier("keyslist.row.\(key.fingerprint)")
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(key.primaryUserID), \(key.hasSecret ? "key.type.keyPair".localized : "key.type.publicOnly".localized)")
            }
            TableColumn("table.fingerprint") { key in
                Text(key.fingerprint.groupedFingerprintAbbreviated)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130, max: 150)
            TableColumn("table.type") { key in
                Text(key.hasSecret ? "key.type.keyPair".localized : "key.type.publicOnly".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 76, ideal: 88, max: 110)
        }
        .accessibilityIdentifier("keyslist.table")
    }

    @ViewBuilder
    private func contextMenu(for key: KeyInfo) -> some View {
        if let onDoubleTap {
            Button("contextmenu.showDetails") { onDoubleTap(key) }
        }
        if let onExport {
            Button("detail.exportPublic") { onExport(key) }
        }
        if let onCopyFingerprint {
            Button("contextmenu.copyFingerprint") { onCopyFingerprint(key) }
        }
        if let onRefresh {
            Divider()
            Button("contextmenu.refresh") { onRefresh() }
        }
        if let onDelete {
            Divider()
            Button("detail.deleteKey", role: .destructive) { onDelete(key) }
        }
    }
}

/// Small colored shield glyph summarizing the trust state of a recipient key.
private struct TrustIndicator: View {
    let state: TrustState

    var body: some View {
        let presentation = TrustPresentation(state: state)
        Image(systemName: presentation.iconName)
            .foregroundStyle(presentation.color)
            .imageScale(.small)
            .accessibilityHidden(true)
    }
}

#if DEBUG
struct KeysListView_Previews: PreviewProvider {
    static var previews: some View {
        KeysListView(keys: [], selection: .constant(nil))
    }
}
#endif
