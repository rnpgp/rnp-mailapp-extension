//
//  KeysListView.swift
//  Ribose container
//
//  Table of the OpenPGP keys in the shared keyring.
//

import MailSecurityEngine
import SwiftUI

struct KeysListView: View {
    let keys: [KeyInfo]
    @Binding var selection: KeyInfo.ID?

    var body: some View {
        Table(keys, selection: $selection) {
            TableColumn("User ID") { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.primaryUserID)
                    HStack(spacing: 6) {
                        Text(key.algorithmLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if key.isRevoked {
                            Badge(text: "Revoked", color: .red)
                        } else if key.isExpired {
                            Badge(text: "Expired", color: .red)
                        } else if let days = key.daysUntilExpiry, days < 60 {
                            Badge(text: "Expires in \(days)d", color: .orange)
                        }
                    }
                }
            }
            TableColumn("Fingerprint") { key in
                Text(key.fingerprint.groupedFingerprint)
                    .font(.system(.body, design: .monospaced))
            }
            TableColumn("Type") { key in
                Text(key.hasSecret ? "Key pair" : "Public only")
            }
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
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 1)
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
