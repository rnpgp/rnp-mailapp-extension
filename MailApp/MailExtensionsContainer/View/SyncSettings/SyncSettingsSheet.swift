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

    init(config: SyncConfiguration = SyncConfiguration()) {
        _config = StateObject(wrappedValue: config)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RnpSpacing.lg) {
                canonicalSection
                passphraseSection
                importSourcesSection
                noticesSection
                actionButtons
            }
            .padding(RnpSpacing.xl)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationTitle("sync.title")
        .accessibilityIdentifier("sync.sheet")
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
        HStack {
            Spacer()
            Button("button.done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sync.done")
        }
    }

    // MARK: Helpers

    /// The CloudKit option isn't fully implemented yet; gate it.
    private func isAvailable(_ id: String) -> Bool {
        if id == "rnp-cloudkit" { return false }  // TODO 35
        return true
    }
}
