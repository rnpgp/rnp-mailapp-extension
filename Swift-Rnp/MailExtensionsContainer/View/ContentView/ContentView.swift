//
//  ContentView.swift
//  Ribose container
//
//  Key manager window: toolbar with generate/import/export/delete actions
//  above the key list.
//

import AppKit
import KeyLifecycle
import MailSecurityEngine
import RnpMailUI
import SwiftUI
import TrustStore
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

            trustConflictsBanner

            expiryBanner

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
                    trustState: model.trustState(for: key),
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
        .sheet(isPresented: $model.showExtendExpirySheet) {
            extendExpirySheet
        }
        .sheet(isPresented: $model.showRevokeConfirmation) {
            revokeConfirmationSheet
        }
        .sheet(isPresented: $model.showRotateSheet) {
            rotateConfirmationSheet
        }
        .sheet(isPresented: $model.showPublishSheet) {
            publishSheet
        }
        .sheet(isPresented: $model.showFetchSheet) {
            fetchSheet
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
        .onOpenURL { url in
            guard url.scheme == "rnpmail",
                  url.host == "review",
                  let fingerprint = url.pathComponents.dropFirst().first,
                  !fingerprint.isEmpty
            else {
                return
            }
            model.openReview(fingerprint: fingerprint)
        }
        .onChange(of: model.manager.keys) { _ in
            if let fingerprint = model.pendingReviewFingerprint {
                model.openReview(fingerprint: fingerprint)
            }
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
                if model.selectedTab == .recipients {
                    Button("From Keyserver…") {
                        model.showFetchSheet = true
                    }
                }
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
            onExtendExpiry: {
                model.showDetailSheet = false
                model.showExtendExpirySheet = true
            },
            onRevoke: {
                model.showDetailSheet = false
                model.showRevokeConfirmation = true
            },
            onRotateEncryption: {
                model.showDetailSheet = false
                model.rotateMessage = "A new encryption subkey will be generated and the old one retired after a 30-day grace period."
                model.showRotateSheet = true
            },
            onRotateSigning: {
                model.showDetailSheet = false
                model.rotateMessage = "A new signing subkey will be generated. Recipients should refresh your public key."
                model.showRotateSheet = true
            },
            onPublish: {
                model.showDetailSheet = false
                model.publishMessage = "Uploading public key to keys.openpgp.org…"
                model.showPublishSheet = true
                model.publishSelectedKey()
            },
            onMarkVerified: {
                model.markSelectedVerified()
            }
        )
    }

    private var expiryBanner: some View {
        let report = model.expiryReport()
        guard let first = report.first else { return AnyView(EmptyView()) }
        let suffix = report.count > 1 ? " (and \(report.count - 1) more)" : ""
        let label = first.isExpired
            ? "Expired: \(first.userID)\(suffix)"
            : "Expiring soon: \(first.userID)\(suffix)"
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: first.isExpired ? "exclamationmark.octagon" : "exclamationmark.triangle")
                Text(label)
                    .font(.callout)
                Spacer()
            }
            .foregroundStyle(.red)
            .padding(.horizontal)
        )
    }

    private var trustConflictsBanner: some View {
        let conflicts = model.trustConflicts
        guard let first = conflicts.first else { return AnyView(EmptyView()) }
        let suffix = conflicts.count > 1 ? " (and \(conflicts.count - 1) more)" : ""
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                Text("Key changed for \(first.email)\(suffix). Verify the new fingerprint before encrypting.")
                    .font(.callout)
                Spacer()
            }
            .foregroundStyle(.orange)
            .padding(.horizontal)
        )
    }

    private var extendExpirySheet: some View {
        VStack(spacing: 16) {
            Text("Extend expiry")
                .font(.headline)
            DatePicker(
                "New expiration date",
                selection: $model.extendExpiryDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            HStack(spacing: 12) {
                Button("Cancel") { model.showExtendExpirySheet = false }
                Button("Extend") {
                    model.showExtendExpirySheet = false
                    model.extendSelectedExpiry()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private var revokeConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revoke key")
                .font(.headline)
            Text("Type the full fingerprint of the key to revoke it. A revocation certificate will be saved to the keyring directory.")
                .font(.callout)
            TextField("Fingerprint", text: $model.revokeFingerprintInput)
                .textFieldStyle(.roundedBorder)
            TextField("Reason (optional)", text: $model.revokeReason)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { model.showRevokeConfirmation = false }
                Button("Revoke", role: .destructive) {
                    model.showRevokeConfirmation = false
                    model.revokeSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.revokeFingerprintInput.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var rotateConfirmationSheet: some View {
        VStack(spacing: 16) {
            Text("Rotate subkey")
                .font(.headline)
            Text(model.rotateMessage)
                .font(.callout)
            HStack(spacing: 12) {
                Button("Cancel") { model.showRotateSheet = false }
                Button("Rotate") {
                    model.showRotateSheet = false
                    if model.rotateMessage.contains("encryption") {
                        model.rotateEncryptionSubkey()
                    } else {
                        model.rotateSigningSubkey()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var publishSheet: some View {
        VStack(spacing: 16) {
            Text("Publish public key")
                .font(.headline)
            Text(model.publishMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("OK") { model.showPublishSheet = false }
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var fetchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fetch key from keyserver")
                .font(.headline)
            Text("Enter an email address or fingerprint:")
                .font(.callout)
            TextField("Email or fingerprint", text: $model.fetchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            if let key = model.fetchedKey {
                Text("Found key from \(key.source)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    model.showFetchSheet = false
                    model.fetchQuery = ""
                    model.fetchedKey = nil
                }
                Button("Search") {
                    model.discoverKey()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.fetchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                if model.fetchedKey != nil {
                    Button("Import") {
                        model.importFetchedKey()
                    }
                }
            }
        }
        .padding()
        .frame(width: 420)
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
