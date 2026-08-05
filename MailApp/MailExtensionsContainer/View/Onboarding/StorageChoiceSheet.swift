//
//  StorageChoiceSheet.swift
//  RNP
//
//  Shown before the standard OnboardingView on first launch. Lets the
//  user pick where RNP keeps its keys. Choice persists via
//  SyncConfiguration.canonicalStoreID.
//
//  See TODO.complete/31-getting-started-storage-choice.md.
//

import RnpMailUI
import SwiftUI

struct StorageChoiceSheet: View {
    @ObservedObject var config: SyncConfiguration
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ascDirPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            header
            ForEach(SyncConfiguration.canonicalOptions) { option in
                storageRow(option)
            }
            if config.canonicalStoreID == "rnp-asc-dir" {
                ascDirPicker
            }
            notices
            Spacer()
            actionButtons
        }
        .padding(RnpSpacing.xl)
        .frame(width: 540, height: 580)
        .accessibilityIdentifier("onboarding.storage-choice")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xxs) {
            Text("storageChoice.title").font(.title2.weight(.semibold))
            Text("storageChoice.subtitle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func storageRow(_ option: CanonicalOption) -> some View {
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
                        Text("storageChoice.unavailable").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityIdentifier("onboarding.storage.\(option.id)")
    }

    private var ascDirPicker: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            Text("storageChoice.ascDirPrompt")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("~/Sync/rnp-keys", text: $ascDirPath)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: ascDirPath) { _, newPath in
                        config.perKeyDirectoryPath = newPath
                    }
                Button("storageChoice.browse") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        ascDirPath = url.path
                        config.perKeyDirectoryPath = url.path
                    }
                }
            }
        }
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xxs) {
            Label("storageChoice.notice.neverDelete", systemImage: "checkmark.shield.fill")
                .font(.caption).foregroundStyle(.secondary)
            Label("storageChoice.notice.readOnlyImports", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
            Label("storageChoice.notice.changeLater", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("storageChoice.skip") {
                config.canonicalStoreID = "rnp-local"
                onComplete()
            }
            Spacer()
            Button("storageChoice.continue") { onComplete() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.storage.continue")
        }
    }

    private func isAvailable(_ id: String) -> Bool {
        if id == "rnp-cloudkit" { return false }
        return true
    }
}
