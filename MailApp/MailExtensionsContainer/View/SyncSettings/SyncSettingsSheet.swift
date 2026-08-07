//
//  SyncSettingsSheet.swift
//  RNP
//
//  Sheet for choosing canonical store, import sources, and passphrase
//  store. See TODO.complete/32-sync-settings-ui.md.
//

import RnpMailUI
import SwiftUI

struct SyncSettingsSheet: View {
    @StateObject private var config: SyncConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var migrationResult: MigrationResult?
    @State private var conflictCount: Int = 0
    @State private var deletionCount: Int = 0
    @State private var showConflictReview = false
    @State private var showDeletionReview = false

    init(config: SyncConfiguration = SyncConfiguration()) {
        _config = StateObject(wrappedValue: config)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RnpSpacing.lg) {
                canonicalSection
                passphraseSection
                importSourcesSection
                conflictsSection
                deletionsSection
                noticesSection
                actionButtons
            }
            .padding(RnpSpacing.xl)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationTitle("sync.title")
        .accessibilityIdentifier("sync.sheet")
        .sheet(isPresented: $showConflictReview) {
            ConflictReviewSheet()
        }
        .sheet(isPresented: $showDeletionReview) {
            RemoteDeletionReviewSheet()
        }
        .onAppear {
            refreshConflictCount()
            refreshDeletionCount()
        }
    }

    // MARK: Canonical store

    private var canonicalSection: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.sm) {
            Text("sync.canonical.title").font(.headline)
            Text("sync.canonical.subtitle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SyncConfiguration.canonicalOptions) { option in
                canonicalRow(option)
            }
            if config.canonicalStoreID == "rnp-asc-dir" {
                perKeyDirPicker
            }
        }
    }

    private func canonicalRow(_ option: CanonicalOption) -> some View {
        let selected = config.canonicalStoreID == option.id
        let available = isAvailable(option.id)
        return Button {
            if available { config.canonicalStoreID = option.id }
        } label: {
            HStack(alignment: .top, spacing: RnpSpacing.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(available ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.body.weight(selected ? .semibold : .regular))
                    Text(option.description)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !available {
                        Text("sync.unavailable").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityIdentifier("sync.canonical.\(option.id)")
    }

    private var perKeyDirPicker: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            Text("sync.canonical.ascDirPath").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("", text: $config.perKeyDirectoryPath, prompt: Text("sync.canonical.ascDirPlaceholder"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("sync.canonical.asc-dir-path")
                Button("sync.canonical.browse") { pickDirectory() }
                    .accessibilityIdentifier("sync.canonical.asc-dir-browse")
            }
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = NSLocalizedString("sync.canonical.browseMessage", comment: "")
        if panel.runModal() == .OK, let url = panel.url {
            config.perKeyDirectoryPath = url.path
        }
    }

    // MARK: Passphrase store

    private var passphraseSection: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.sm) {
            Text("sync.passphrase.title").font(.headline)
            Text("sync.passphrase.subtitle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SyncConfiguration.passphraseStoreOptions) { option in
                passphraseRow(option)
            }
        }
    }

    private func passphraseRow(_ option: PassphraseOption) -> some View {
        let selected = config.passphraseStoreID == option.id
        return Button {
            config.passphraseStoreID = option.id
        } label: {
            HStack(alignment: .top, spacing: RnpSpacing.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.body.weight(selected ? .semibold : .regular))
                    Text(option.description)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sync.passphrase.\(option.id)")
    }

    // MARK: Import sources

    private var importSourcesSection: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.sm) {
            Text("sync.sources.title").font(.headline)
            Text("sync.sources.subtitle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SyncConfiguration.importSourceOptions) { option in
                importSourceRow(option)
            }
        }
    }

    private func importSourceRow(_ option: ImportSourceOption) -> some View {
        let enabled = config.enabledImportSources.contains(option.id)
        return Toggle(isOn: Binding(
            get: { enabled },
            set: { isOn in
                if isOn { config.enabledImportSources.insert(option.id) }
                else { config.enabledImportSources.remove(option.id) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.body)
                Text(option.description)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("sync.sources.\(option.id)")
    }

    // MARK: Conflicts

    /// Shown only when the active backend is the per-key `.asc`
    /// directory (the only backend that surfaces conflicts). For
    /// local-only and CloudKit, this section is hidden.
    @ViewBuilder
    private var conflictsSection: some View {
        if config.canonicalStoreID == "rnp-asc-dir" {
            VStack(alignment: .leading, spacing: RnpSpacing.xs) {
                HStack {
                    Text("sync.conflicts.title").font(.headline)
                    Spacer()
                    Button("sync.conflicts.review") { showConflictReview = true }
                        .accessibilityIdentifier("sync.conflicts.review")
                }
                if conflictCount > 0 {
                    Label(String(format: NSLocalizedString("sync.conflicts.count", comment: ""), conflictCount),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Label("sync.conflicts.none", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshConflictCount() {
        if let backend = KeyringCoordinator.shared?.backend as? PerKeyDirectoryKeyringBackend {
            conflictCount = backend.listConflicts().count
        } else {
            conflictCount = 0
        }
    }

    // MARK: Remote deletions

    /// Shown only when the active backend is not rnp-local — local
    /// backends never produce pending remote deletions.
    @ViewBuilder
    private var deletionsSection: some View {
        if config.canonicalStoreID != "rnp-local" {
            VStack(alignment: .leading, spacing: RnpSpacing.xs) {
                HStack {
                    Text("sync.deletions.title").font(.headline)
                    Spacer()
                    Button("sync.deletions.review") { showDeletionReview = true }
                        .accessibilityIdentifier("sync.deletions.review")
                }
                if deletionCount > 0 {
                    Label(String(format: NSLocalizedString("sync.deletions.count", comment: ""), deletionCount),
                          systemImage: "trash")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Label("sync.deletions.none", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshDeletionCount() {
        deletionCount = KeyringCoordinator.shared?.pendingRemoteDeletions.count ?? 0
    }

    // MARK: Notices

    private var noticesSection: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            Label("sync.notice.neverDelete", systemImage: "checkmark.shield.fill")
                .font(.caption).foregroundStyle(.secondary)
            Label("sync.notice.importsReadOnly", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
            Label("sync.notice.cloudKitStub", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, RnpSpacing.sm)
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(alignment: .trailing, spacing: RnpSpacing.xs) {
            if let result = migrationResult {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.success ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("button.done") { commitAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sync.done")
            }
        }
    }

    /// If the user changed the canonical store, run the migration
    /// (copies all local keys into the new backend, then flips the
    /// active reference). On success, dismiss. On failure, surface
    /// the message inline so the user can retry or pick a different
    /// store; don't dismiss.
    private func commitAndDismiss() {
        let targetID = config.canonicalStoreID
        guard let coordinator = KeyringCoordinator.shared else {
            migrationResult = MigrationResult(success: false,
                                              message: NSLocalizedString("sync.migration.noCoordinator", comment: ""))
            return
        }
        // Per-key .asc dir requires a non-empty path before we can migrate.
        if targetID == "rnp-asc-dir" && config.perKeyDirectoryPath.isEmpty {
            migrationResult = MigrationResult(success: false,
                                              message: NSLocalizedString("sync.migration.noAscPath", comment: ""))
            return
        }
        do {
            let copied = try coordinator.migrate(to: targetID)
            migrationResult = MigrationResult(
                success: true,
                message: String(format: NSLocalizedString("sync.migration.success", comment: ""), copied)
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { dismiss() }
        } catch {
            migrationResult = MigrationResult(success: false, message: error.localizedDescription)
        }
    }

    private struct MigrationResult {
        let success: Bool
        let message: String
    }

    // MARK: Helpers

    /// CloudKit is fully implemented. Available iff signed into iCloud.
    private func isAvailable(_ id: String) -> Bool {
        if id == "rnp-cloudkit" {
            return CloudKitKeyringBackend().availability == .available
        }
        return true
    }
}
