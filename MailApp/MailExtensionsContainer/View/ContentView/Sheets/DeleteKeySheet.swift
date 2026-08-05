//
//  DeleteKeySheet.swift
//  RNP
//
//  Three-step delete flow with mandatory encrypted backup. Replaces
//  the old single-alert delete confirmation. See
//  DeletionConfirmationState for the state machine.
//

import MailSecurityEngine
import RnpMailUI
import SwiftUI

struct DeleteKeySheet: View {
    @ObservedObject var model: ContentViewModel
    @StateObject private var state: DeletionConfirmationState
    @Environment(\.dismiss) private var dismiss

    init(model: ContentViewModel, fingerprints: [String], primaryUserIDs: [String]) {
        self.model = model
        _state = StateObject(wrappedValue: DeletionConfirmationState(
            fingerprints: fingerprints,
            primaryUserIDs: primaryUserIDs
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            header
            Divider()
            Group {
                switch state.step {
                case .warning:       warningStep
                case .typeToConfirm: typeToConfirmStep
                case .finalWarning:  finalWarningStep
                case .working:       workingStep
                case .done(let summary): doneStep(summary)
                case .failed(let msg): failedStep(msg)
                }
            }
        }
        .padding(RnpSpacing.xl)
        .frame(width: 520)
        .accessibilityIdentifier("contentview.delete.sheet")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: RnpSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(RnpBrand.critical)
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RnpSpacing.xxs) {
                Text("deleteKey.sheet.title")
                    .font(.title3.weight(.semibold))
                Text(state.fingerprints.count == 1
                     ? state.primaryUserIDs.first ?? state.fingerprints.first ?? ""
                     : "\(state.fingerprints.count) keys")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: Step 1 — Warning

    private var warningStep: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            Text("deleteKey.step1.body")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("deleteKey.step1.recoverable")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("button.cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("deleteKey.step1.continue") { state.advanceFromWarning() }
                    .buttonStyle(.borderedProminent)
                    .tint(RnpBrand.critical)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Step 2 — Type to confirm

    private var typeToConfirmStep: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            Text("deleteKey.step2.body")
                .font(.body)
            Text(state.expectedConfirmationText)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(RnpSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: RnpRadius.badge, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            TextField("", text: $state.typedConfirmation)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("contentview.delete.type-confirm")
            HStack {
                Button("button.back") { state.back() }
                Spacer()
                Button("deleteKey.step2.continue") { state.advanceFromTypeConfirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(RnpBrand.critical)
                    .disabled(!state.isTypedConfirmationValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Step 3 — Final warning + passphrase + path

    private var finalWarningStep: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            Text("deleteKey.step3.body")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("deleteKey.step3.backupWillBeSaved")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Text("deleteKey.step3.backupPath")
                    .font(.caption)
                Spacer()
                Button("deleteKey.step3.choosePath") { choosePath() }
                    .accessibilityIdentifier("contentview.delete.choose-path")
            }
            if let url = state.backupURL {
                Text(url.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            SecureField("deleteKey.step3.passphrase", text: $state.passphrase)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.delete.passphrase")
            SecureField("deleteKey.step3.confirmPassphrase", text: $state.confirmPassword)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.delete.confirm-passphrase")
            if !state.passphrase.isEmpty, !state.isPassphraseValid {
                Text("deleteKey.step3.passphraseMismatch")
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .accessibilityIdentifier("contentview.delete.mismatch-warning")
            }
            HStack {
                Button("button.back") { state.back() }
                Spacer()
                Button("deleteKey.step3.deleteForever", role: .destructive) {
                    performDelete()
                }
                .buttonStyle(.borderedProminent)
                .tint(RnpBrand.critical)
                .disabled(!state.canProceedToDelete)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("contentview.delete.confirm")
            }
        }
    }

    // MARK: Working

    private var workingStep: some View {
        HStack(spacing: RnpSpacing.sm) {
            ProgressView().controlSize(.small)
            Text("deleteKey.working").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, RnpSpacing.md)
    }

    // MARK: Done

    private func doneStep(_ summary: BackupSummary) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            HStack(spacing: RnpSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.green)
                Text("deleteKey.done.title").font(.headline)
            }
            Text("deleteKey.done.body")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(summary.url.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
            Text(String(format: "deleteKey.done.summary".localized,
                        summary.fingerprintCount,
                        ByteCountFormatter.string(fromByteCount: Int64(summary.byteCount), countStyle: .file)))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("deleteKey.done.reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([summary.url])
                }
                Spacer()
                Button("button.done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Failed

    private func failedStep(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            HStack(spacing: RnpSpacing.sm) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(RnpBrand.critical)
                Text("deleteKey.failed.title").font(.headline)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("deleteKey.failed.notDeleted")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("button.done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Actions

    private func choosePath() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = state.backupURL?.lastPathComponent ?? KeyBackupArchive.suggestedFilename()
        panel.canCreateDirectories = true
        panel.message = NSLocalizedString("deleteKey.step3.panelMessage", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.backupURL = url
    }

    private func performDelete() {
        guard let url = state.backupURL else { return }
        state.step = .working
        let fprs = state.fingerprints
        let pw = state.passphrase
        let mgr = model.manager
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let summary = try KeyBackupArchive.write(
                    fingerprints: fprs,
                    passphrase: pw,
                    to: url,
                    using: mgr
                )
                DispatchQueue.main.async {
                    // Backup succeeded; now actually delete from the
                    // canonical store. We DON'T catch delete errors
                    // because the backup is already safe — surface
                    // them but don't roll back the backup.
                    for fpr in fprs {
                        if let key = mgr.keys.first(where: { $0.fingerprint == fpr }) {
                            mgr.delete(key)
                        }
                    }
                    state.step = .done(summary)
                }
            } catch {
                DispatchQueue.main.async {
                    state.step = .failed(error.localizedDescription)
                }
            }
        }
    }
}
