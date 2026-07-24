//
//  PaperKeyPrintView.swift
//  RnpMailUI
//
//  Printable layout for the paper-key backup. Uses NSPrintOperation
//  to produce a standard Mac print dialog. The layout includes:
//  - header with fingerprint, algorithm, date
//  - the hex body in monospaced columns
//  - instructions for restoration
//
//  QR code generation is deferred to a future iteration; the hex
//  text alone is sufficient for the paperkey tool's restore path.
//

import MailSecurityEngine
import SwiftUI
import AppKit

/// View formatted for printing the paper-key backup. The caller
/// passes the paper-key text (from KeyManager.exportPaperKey) and
/// the view renders it in a printable layout.
public struct PaperKeyPrintView: View {
    public let paperKeyText: String
    public let fingerprint: String

    public init(paperKeyText: String, fingerprint: String) {
        self.paperKeyText = paperKeyText
        self.fingerprint = fingerprint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RNP Paper-Key Backup")
                .font(.title.bold())

            Text("Fingerprint: \(fingerprint)")
                .font(.headline)
                .accessibilityIdentifier("paperkey-print.fingerprint")

            Text("Instructions")
                .font(.headline)
            Text(instructions)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Secret-key data (hex):")
                .font(.headline)
            ScrollView {
                Text(paperKeyText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 400)
        }
        .padding(40)
        .frame(width: 612, height: 792) // US Letter at 72dpi
    }

    private var instructions: String {
        """
        Store this page in a safe, offline location. Anyone with this paper \
        and your keyring passphrase can read your encrypted mail.

        To restore: open the RNP app → Settings → Restore from backup → \
        paste or type the hex text below. Or use the upstream paperkey tool: \
        paperkey --restore < this-text | gpg --import
        """
    }
}

/// Helper that presents the system print dialog for a paper-key.
public enum PaperKeyPrinter {
    /// Presents `NSPrintOperation` for the given paper-key text.
    /// The caller ensures the keyring's secret export has already
    /// produced the text via `KeyManager.exportPaperKey`.
    public static func print(paperKeyText: String, fingerprint: String) {
        let view = PaperKeyPrintView(
            paperKeyText: paperKeyText,
            fingerprint: fingerprint
        )
        let hosting = NSHostingView(rootView: view)
        let printOperation = NSPrintOperation(view: hosting)
        printOperation.run()
    }
}
