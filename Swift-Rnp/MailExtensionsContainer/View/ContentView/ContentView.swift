//
//  ContentView.swift
//  Ribose container
//
//  Key manager window: toolbar with generate/import/export/delete actions
//  above the key list.
//

import AppKit
import MailSecurityEngine
import RnpMailUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        VStack(spacing: 12) {
            header

            Picker("Tab", selection: $model.selectedTab) {
                ForEach(KeyTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            toolbar

            KeysListView(
                keys: model.keys,
                selection: $model.selection,
                onDoubleTap: { _ in model.showDetailSheet = true }
            )
            .onDrop(of: [.fileURL, .data, .plainText], isTargeted: .constant(false)) { providers in
                handleDrop(providers: providers)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 400)
        .sheet(isPresented: $model.showGenerateSheet) {
            GenerateKeySheet(algorithm: model.generateAlgorithm) { userID, algorithm in
                model.generate(userID: userID, algorithm: algorithm)
            }
        }
        .sheet(isPresented: $model.showDetailSheet) {
            if let key = model.selectedKey {
                KeyDetailView(
                    key: key,
                    subkeys: model.manager.subkeys(for: key),
                    isRecipient: model.selectedTab == .recipients,
                    actions: detailActions(for: key)
                )
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(
                isPresented: $model.showOnboarding,
                onGenerate: { userID, algorithm, passphrase, expirationSeconds, useTouchID in
                    model.generateForOnboarding(
                        userID: userID,
                        algorithm: algorithm,
                        passphrase: passphrase,
                        expirationSeconds: expirationSeconds,
                        useTouchID: useTouchID
                    )
                },
                onImport: { data in
                    model.importForOnboarding(data)
                },
                onComplete: {
                    model.markOnboardingComplete()
                }
            )
        }
        .sheet(isPresented: $model.showClipboardImport) {
            clipboardImportSheet
        }
        .alert("Delete key?", isPresented: $model.showDeleteConfirmation) {
            Button("Delete", role: .destructive) { model.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the key from the shared keyring. This cannot be undone.")
        }
        .alert(
            "Key operation failed",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(
            model.warningMessage ?? "",
            isPresented: Binding(
                get: { model.warningMessage != nil },
                set: { if !$0 { model.warningMessage = nil } }
            )
        ) {
            Button("OK") { model.warningMessage = nil }
        }
        .onAppear {
            model.checkOnboarding()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkClipboardForPGP()
        }
    }

    private var header: some View {
        Text("OpenPGP Keys")
            .font(.title2)
    }

    private var toolbar: some View {
        HStack(spacing: 24) {
            Menu {
                Button("Ed25519") { model.beginGenerate(algorithm: .ed25519) }
                Button("RSA-3072") { model.beginGenerate(algorithm: .rsa) }
                Button("ECDSA P-256") { model.beginGenerate(algorithm: .ecdsa) }
            } label: {
                Image(systemName: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Generate a new key")

            Menu {
                Button("From Clipboard") { model.importFromPasteboard() }
                Button("From File…") { model.importFromFile() }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .help("Import an armored key")

            Button {
                model.exportSelectedPublicToPasteboard()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedKey == nil)
            .help("Copy the armored public key to the clipboard")

            Button {
                model.showDetailSheet = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedKey == nil)
            .help("Show key details")

            Button {
                model.showDeleteConfirmation = true
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedKey == nil)
            .help("Delete the selected key")
        }
        .font(.system(size: 32))
    }

    private func detailActions(for key: KeyInfo) -> KeyDetailActions {
        KeyDetailActions(
            onExportPublic: { model.exportSelectedPublicToPasteboard() },
            onExportSecret: { model.exportSelectedSecretToPasteboard() },
            onDelete: {
                model.showDetailSheet = false
                model.showDeleteConfirmation = true
            },
            onExtendExpiry: {},
            onRevoke: {}
        )
    }

    private var clipboardImportSheet: some View {
        VStack(spacing: 16) {
            Text("Import key from clipboard?")
                .font(.headline)
            Text("The clipboard contains an armored OpenPGP key block.")
                .font(.callout)
            HStack(spacing: 12) {
                Button("Cancel") {
                    model.showClipboardImport = false
                    model.clipboardText = ""
                }
                Button("Import") {
                    model.confirmClipboardImport()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else {
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        guard let keyData = try? Data(contentsOf: url) else { return }
                        DispatchQueue.main.async {
                            model.importData(keyData)
                        }
                    }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string = string, string.contains("BEGIN PGP") else { return }
                    DispatchQueue.main.async {
                        model.importData(Data(string.utf8))
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, _ in
                    guard let data = item as? Data else { return }
                    DispatchQueue.main.async {
                        model.importData(data)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

/// Sheet collecting the user ID for a new key.
private struct GenerateKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userID = ""

    let algorithm: KeyAlgorithm
    let onGenerate: (String, KeyAlgorithm) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate key (\(algorithm.rawValue))")
                .font(.headline)
            Text("User ID, e.g. “Alice <alice@example.com>”:")
                .font(.callout)
            TextField("Name <email>", text: $userID)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Generate") {
                    onGenerate(userID, algorithm)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(userID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: ContentViewModel(manager: KeysManager()))
    }
}
#endif
