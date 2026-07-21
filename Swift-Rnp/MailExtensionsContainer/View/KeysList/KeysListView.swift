//
//  KeysListView.swift
//  Ribose container
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

    init(
        keys: [KeyInfo],
        selection: Binding<KeyInfo.ID?>,
        trustState: ((KeyInfo) -> TrustState?)? = nil,
        onDoubleTap: ((KeyInfo) -> Void)? = nil,
        onExport: ((KeyInfo) -> Void)? = nil,
        onCopyFingerprint: ((KeyInfo) -> Void)? = nil,
        onDelete: ((KeyInfo) -> Void)? = nil
    ) {
        self.keys = keys
        self._selection = selection
        self.trustState = trustState
        self.onDoubleTap = onDoubleTap
        self.onExport = onExport
        self.onCopyFingerprint = onCopyFingerprint
        self.onDelete = onDelete
    }

    var body: some View {
        Table(keys, selection: $selection) {
            TableColumn("table.userID") { key in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(key.primaryUserID)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let state = trustState?(key) {
                            TrustIndicator(state: state)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(key.algorithmLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if key.isRevoked {
                            Badge(text: "badge.revoked".localized, color: .red)
                        } else if key.isExpired {
                            Badge(text: "badge.expired".localized, color: .red)
                        } else if let days = key.daysUntilExpiry, days < 60 {
                            Badge(text: String(format: "badge.expiresIn".localized, days), color: .orange)
                        }
                    }
                }
                .padding(.vertical, 2)
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
                Text(key.fingerprint.groupedFingerprint)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 150, max: 170)
            TableColumn("table.type") { key in
                Text(key.hasSecret ? "key.type.keyPair".localized : "key.type.publicOnly".localized)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 96, max: 120)
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
        Image(systemName: iconName)
            .foregroundStyle(color)
            .imageScale(.small)
            .accessibilityHidden(true)
    }

    private var iconName: String {
        switch state {
        case .verified:
            return "checkmark.shield.fill"
        case .problem:
            return "exclamationmark.shield.fill"
        case .unverified:
            return "questionmark.shield"
        }
    }

    private var color: Color {
        switch state {
        case .verified:
            return .green
        case .problem:
            return .red
        case .unverified:
            return .orange
        }
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
    /// "AB12 CD34 …" rendering of a hex fingerprint (first 16 chars).
    var groupedFingerprint: String {
        let prefix = String(prefix(16))
        return stride(from: 0, to: prefix.count, by: 4)
            .map { offset -> String in
                let start = prefix.index(prefix.startIndex, offsetBy: offset)
                let end = prefix.index(start, offsetBy: 4, limitedBy: prefix.endIndex) ?? prefix.endIndex
                return String(prefix[start ..< end])
            }
            .joined(separator: " ") + " …"
    }
}

#if DEBUG
struct KeysListView_Previews: PreviewProvider {
    static var previews: some View {
        KeysListView(keys: [], selection: .constant(nil))
    }
}
#endif
