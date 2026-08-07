//
//  RemoteDeletionReviewSheet.swift
//  RNP
//
//  Lists keys that another device deleted from the shared backend
//  while they were still in this Mac's local cache. Per entry the
//  user picks: also delete locally (accept the remote decision), or
//  keep locally (reject — the key gets re-propagated on the next
//  mutation that touches it).
//
//  Read from `KeyringCoordinator.pendingRemoteDeletions`. Only shown
//  when the active backend is remote-synced (`.asc` dir / CloudKit);
//  rnp-local never produces pending deletions.
//

import RnpMailUI
import SwiftUI

struct RemoteDeletionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: [String] = []
    @State private var resolving: String?

    private var coordinator: KeyringCoordinator? { KeyringCoordinator.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            header
            Divider()
            if pending.isEmpty {
                emptyState
            } else {
                deletionList
            }
            Divider()
            footer
        }
        .padding(RnpSpacing.lg)
        .frame(width: 560, height: 460)
        .navigationTitle("remoteDeletion.title")
        .accessibilityIdentifier("remote-deletion.sheet")
        .onAppear { reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            Text("remoteDeletion.title").font(.title2).fontWeight(.semibold)
            Text("remoteDeletion.subtitle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: RnpSpacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("remoteDeletion.empty").font(.headline)
            Text("remoteDeletion.emptyDetail")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deletionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RnpSpacing.sm) {
                ForEach(pending, id: \.self) { fpr in
                    deletionRow(fpr)
                }
            }
        }
    }

    private func deletionRow(_ fpr: String) -> some View {
        let isResolving = resolving == fpr
        return HStack(alignment: .firstTextBaseline, spacing: RnpSpacing.sm) {
            Image(systemName: "trash")
                .foregroundStyle(.orange)
            Text(fpr).font(.system(.body, design: .monospaced))
            Spacer()
            Button("remoteDeletion.keep") { resolve(fpr, deleteLocally: false) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("remote-deletion.keep.\(fpr)")
            Button("remoteDeletion.deleteLocal") { resolve(fpr, deleteLocally: true) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("remote-deletion.delete.\(fpr)")
            if isResolving {
                ProgressView().controlSize(.small)
            }
        }
        .padding(RnpSpacing.sm)
        .background(.quaternary, in: .rect(cornerRadius: 6))
        .disabled(isResolving)
    }

    private var footer: some View {
        HStack {
            Button("remoteDeletion.refresh") { reload() }
                .accessibilityIdentifier("remote-deletion.refresh")
            Spacer()
            Button("button.done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("remote-deletion.done")
        }
    }

    private func reload() {
        pending = Array(coordinator?.pendingRemoteDeletions ?? []).sorted()
    }

    private func resolve(_ fpr: String, deleteLocally: Bool) {
        resolving = fpr
        // resolveRemoteDeletion is cheap (one keyring op); hop to
        // background just to keep the UI responsive on slow disks.
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.sync { coordinator?.resolveRemoteDeletion(fpr, deleteLocally: deleteLocally) }
            DispatchQueue.main.async {
                self.resolving = nil
                self.reload()
            }
        }
    }
}
