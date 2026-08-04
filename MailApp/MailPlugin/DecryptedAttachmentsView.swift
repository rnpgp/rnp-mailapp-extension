//
//  DecryptedAttachmentsView.swift
//  MailPlugin
//
//  Companion panel to the security banner: lists attachments that the
//  decoder found encrypted and successfully decrypted. Each row offers
//  a "Save" button. Shown only when `attachments` is non-empty.
//
//  This is host-app code (not in MailSecurityUI) because MailKit's
//  NSSavePanel integration belongs at the host-app layer. The data
//  comes from `MailSecurityEngine.SecurityInformation.decryptedAttachments`.
//

import AppKit
import MailSecurityEngine
import SwiftUI
import os

private let attachmentLog = Logger(subsystem: "com.rnpgp.RNPForMail", category: "mail-attachments")

/// Pure-SwiftUI list of decrypted attachments with per-row Save +
/// "Save all" actions. The view is NSHostingController-friendly so the
/// MailPlugin view controller can embed it below the security banner.
struct DecryptedAttachmentsView: View {
    let attachments: [DecryptedAttachment]

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("decryptedAttachments.title")
                        .font(.headline)
                    Spacer()
                    Button("decryptedAttachments.saveAll") { saveAll() }
                        .accessibilityIdentifier("mail.attachments.save-all")
                }
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                    row(for: attachment)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private func row(for attachment: DecryptedAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.suggestedFilename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("button.save") { save(attachment) }
                .accessibilityIdentifier("mail.attachments.save.\(attachment.suggestedFilename)")
        }
    }

    private func save(_ attachment: DecryptedAttachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.suggestedFilename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try attachment.data.write(to: url, options: .atomic)
        } catch {
            attachmentLog.error("attachment save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for attachment in attachments {
            let url = dir.appendingPathComponent(attachment.suggestedFilename)
            do {
                try attachment.data.write(to: url, options: .atomic)
            } catch {
                attachmentLog.error("attachment saveAll failed for \(attachment.suggestedFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
