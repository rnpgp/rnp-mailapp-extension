//
//  ImportFromKeyringSheet.swift
//  RNP for Mail
//
//  Sheet that auto-detects the user's existing OpenPGP keyrings
//  (~/.gnupg, ~/.rnp) and lets them pick which keys to import into
//  the app's keyring. Source keyrings are read-only — the import is
//  a copy, never a move or write-back.
//

import SwiftUI

struct ImportFromKeyringSheet: View {
    @ObservedObject var model: ContentViewModel
    @State private var discovered: [DiscoveredKeyring] = []
    @State private var selectedKeyIDs: Set<UUID> = []
    @State private var scanError: String?
    @State private var isScanning = true
    @State private var importProgress: (done: Int, total: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("importFromKeyring.title")
                .font(.headline)
            Text("importFromKeyring.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("importFromKeyring.scanning").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else if let scanError {
                Text(scanError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if discovered.isEmpty {
                Text("importFromKeyring.none")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                keyList
            }

            if let progress = importProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(format: "importFromKeyring.importing".localized, progress.done, progress.total))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") { model.currentSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("contentview.import-keyring.cancel")
                Button(String(format: "importFromKeyring.importButton".localized, selectedKeyIDs.count)) {
                    importSelected()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedKeyIDs.isEmpty || importProgress != nil)
                .accessibilityIdentifier("contentview.import-keyring.import")
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { scan() }
    }

    @ViewBuilder
    private var keyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(discovered) { keyring in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(.secondary)
                            Text("\(keyring.source.displayName) — \(keyring.path.path)")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(keyring.keys.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(keyring.keys) { key in
                            KeyImportRow(key: key, isSelected: selectedKeyIDs.contains(key.id)) {
                                toggle(key)
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ key: DiscoveredKey) {
        if selectedKeyIDs.contains(key.id) {
            selectedKeyIDs.remove(key.id)
        } else {
            selectedKeyIDs.insert(key.id)
        }
    }

    private func scan() {
        isScanning = true
        scanError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = KeyringScanner.discoverAll()
            DispatchQueue.main.async {
                discovered = result
                isScanning = false
            }
        }
    }

    private func importSelected() {
        let selected = discovered.flatMap(\.keys).filter { selectedKeyIDs.contains($0.id) }
        importProgress = (done: 0, total: selected.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var done = 0
            for key in selected {
                if let armored = KeyringScanner.exportArmored(key) {
                    DispatchQueue.main.sync {
                        model.importData(armored)
                    }
                }
                done += 1
                DispatchQueue.main.async {
                    importProgress = (done: done, total: selected.count)
                }
            }
            DispatchQueue.main.async {
                importProgress = nil
                model.currentSheet = nil
            }
        }
    }
}

private struct KeyImportRow: View {
    let key: DiscoveredKey
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.primaryUserID)
                        .font(.body)
                    ForEach(Array(key.userIDs.dropFirst().prefix(2)), id: \.self) { uid in
                        Text(uid).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(key.fingerprint.groupedFingerprintBlocks)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if key.hasSecret {
                            Text("importFromKeyring.secret")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contentview.import-keyring.row.\(key.id)")
    }
}
