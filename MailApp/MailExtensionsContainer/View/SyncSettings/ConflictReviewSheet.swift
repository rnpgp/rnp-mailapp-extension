//
//  ConflictReviewSheet.swift
//  RNP
//
//  Lists `<fpr>.asc.conflict-*` files produced by
//  `PerKeyDirectoryKeyringBackend` when an incoming write diverged
//  from the bytes already on disk. For each conflict the user picks
//  which version to keep: the current (local) bytes, or the incoming
//  (remote) bytes that were stashed aside as the conflict file.
//
//  Only shown when the active canonical backend is the per-key `.asc`
//  directory. Local-only and CloudKit backends don't produce conflict
//  files.
//

import RnpMailUI
import SwiftUI

struct ConflictReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var conflicts: [ConflictFile] = []
    @State private var error: String?
    @State private var resolving: String?

    private var ascDirBackend: PerKeyDirectoryKeyringBackend? {
        KeyringCoordinator.shared?.backend as? PerKeyDirectoryKeyringBackend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            header
            Divider()
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            } else if conflicts.isEmpty {
                emptyState
            } else {
                conflictList
            }
            Divider()
            footer
        }
        .padding(RnpSpacing.lg)
        .frame(width: 560, height: 460)
        .navigationTitle("conflictReview.title")
        .accessibilityIdentifier("conflict-review.sheet")
        .onAppear { reload() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            Text("conflictReview.title").font(.title2).fontWeight(.semibold)
            Text("conflictReview.subtitle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: RnpSpacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("conflictReview.empty").font(.headline)
            Text("conflictReview.emptyDetail")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private var conflictList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RnpSpacing.sm) {
                ForEach(conflicts) { conflict in
                    conflictRow(conflict)
                }
            }
        }
    }

    private func conflictRow(_ conflict: ConflictFile) -> some View {
        let isResolving = resolving == conflict.id
        return VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.fingerprint).font(.system(.body, design: .monospaced))
                    Text(String(
                        format: NSLocalizedString("conflictReview.detectedAt", comment: ""),
                        conflict.conflictTimestamp, conflict.byteCount
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("conflictReview.reveal") { NSWorkspace.shared.activateFileViewerSelecting([conflict.url]) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("conflict-review.reveal.\(conflict.id)")
            }
            HStack(spacing: RnpSpacing.sm) {
                Button("conflictReview.keepLocal") {
                    resolve(conflict, action: .keepLocal)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("conflict-review.keep-local.\(conflict.id)")
                Button("conflictReview.keepRemote") {
                    resolve(conflict, action: .keepRemote)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("conflict-review.keep-remote.\(conflict.id)")
                if isResolving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(RnpSpacing.sm)
        .background(.quaternary, in: .rect(cornerRadius: 6))
        .disabled(isResolving)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("conflictReview.refresh") { reload() }
                .accessibilityIdentifier("conflict-review.refresh")
            Spacer()
            Button("button.done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("conflict-review.done")
        }
    }

    // MARK: Actions

    private enum Resolution { case keepLocal, keepRemote }

    private func reload() {
        guard let backend = ascDirBackend else {
            error = NSLocalizedString("conflictReview.wrongBackend", comment: "")
            conflicts = []
            return
        }
        conflicts = backend.listConflicts()
        error = nil
    }

    private func resolve(_ conflict: ConflictFile, action: Resolution) {
        guard let backend = ascDirBackend else { return }
        resolving = conflict.id
        let work = DispatchWorkItem {
            do {
                switch action {
                case .keepLocal:  try backend.resolveConflictKeepLocal(conflict)
                case .keepRemote: try backend.resolveConflictKeepRemote(conflict)
                }
                DispatchQueue.main.async {
                    self.resolving = nil
                    self.reload()
                }
            } catch let err {
                DispatchQueue.main.async {
                    self.error = err.localizedDescription
                    self.resolving = nil
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
