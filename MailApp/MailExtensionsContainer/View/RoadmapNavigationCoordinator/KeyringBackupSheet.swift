//
//  KeyringBackupSheet.swift
//  RNP
//
//  Sheet that triggers KeyringBackupService.backup. NSSavePanel for
//  destination; ditto-zips the keyring; surfaces a manifest summary
//  on success.
//

import AppKit
import MailSecurityEngine
import RnpMailUI
import SwiftUI

struct KeyringBackupSheet: View {
    let keyringDirectory: URL
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .idle
    @State private var errorText: String?
    @State private var manifestSummary: String?

    enum Phase { case idle, working, done }

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            Text("keyringBackup.title")
                .font(.headline)
            Text("keyringBackup.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch phase {
            case .idle:
                HStack {
                    Button("button.cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("keyringBackup.chooseDestination") { runBackup() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .working:
                HStack(spacing: RnpSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("keyringBackup.working").foregroundStyle(.secondary)
                }
            case .done:
                if let summary = manifestSummary {
                    Text(summary)
                        .font(.callout)
                        .padding(RnpSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: RnpRadius.card, style: .continuous)
                                .fill(Color.green.opacity(0.08))
                        )
                }
                HStack {
                    Spacer()
                    Button("button.done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(Color.red).font(.caption)
            }
        }
        .padding(RnpSpacing.xl)
        .frame(width: 460)
        .accessibilityIdentifier("keyring-backup.sheet")
    }

    private func runBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.archive]
        panel.nameFieldStringValue = "rnp-keyring-\(Self.dateStamp()).rnp-keys.zip"
        panel.canCreateDirectories = true
        panel.message = NSLocalizedString("keyringBackup.panelMessage", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        phase = .working
        let dir = keyringDirectory
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let manifest = try KeyringBackupService.backup(
                    from: dir,
                    to: url,
                    appVersion: appVersion,
                    includesSecretKeys: true
                )
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let summary = String(
                    format: NSLocalizedString("keyringBackup.summary", comment: ""),
                    manifest.keyCount,
                    formatter.string(from: manifest.createdAt),
                    url.lastPathComponent
                )
                DispatchQueue.main.async {
                    self.manifestSummary = summary
                    self.phase = .done
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorText = error.localizedDescription
                    self.phase = .idle
                }
            }
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

struct KeyringRestoreSheet: View {
    let keyringDirectory: URL
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .idle
    @State private var errorText: String?
    @State private var reportSummary: String?

    enum Phase { case idle, working, done }

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            Text("keyringRestore.title")
                .font(.headline)
            Text("keyringRestore.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch phase {
            case .idle:
                HStack {
                    Button("button.cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("keyringRestore.chooseArchive") { runRestore() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .working:
                HStack(spacing: RnpSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("keyringRestore.working").foregroundStyle(.secondary)
                }
            case .done:
                if let summary = reportSummary {
                    Text(summary)
                        .font(.callout)
                        .padding(RnpSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: RnpRadius.card, style: .continuous)
                                .fill(Color.green.opacity(0.08))
                        )
                }
                HStack {
                    Spacer()
                    Button("button.done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(Color.red).font(.caption)
            }
        }
        .padding(RnpSpacing.xl)
        .frame(width: 460)
        .accessibilityIdentifier("keyring-restore.sheet")
    }

    private func runRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.archive]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("keyringRestore.panelMessage", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        phase = .working
        let dir = keyringDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try KeyringBackupService.restore(from: url, into: dir)
                let summary = String(
                    format: NSLocalizedString("keyringRestore.summary", comment: ""),
                    report.importedKeys, report.skippedKeys
                )
                DispatchQueue.main.async {
                    self.reportSummary = summary
                    self.phase = .done
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorText = error.localizedDescription
                    self.phase = .idle
                }
            }
        }
    }
}
