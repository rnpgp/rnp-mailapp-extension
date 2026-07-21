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
    @State private var showLicenses = false

    var body: some View {
        VStack(spacing: 12) {
            header

            Picker("tab.selector", selection: $model.selectedTab) {
                ForEach(KeyTab.allCases, id: \.self) { tab in
                    Text(tab.localizedName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("contentview.tab-picker")

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
        .sheet(isPresented: $showLicenses) {
            LicensesView(sourcesMarkdown: LicensesView.loadSources())
        }
        .alert("deleteKey.title", isPresented: $model.showDeleteConfirmation) {
            Button("button.delete", role: .destructive) { model.deleteSelected() }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("deleteKey.message")
        }
        .alert(
            "error.operation.title",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("button.ok") { model.errorMessage = nil }
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
            Button("button.ok") { model.warningMessage = nil }
        }
        .onAppear {
            model.checkOnboarding()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkClipboardForPGP()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLicenses)) { _ in
            showLicenses = true
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
        Text("title.keysManager")
            .font(.title2)
    }

    private var toolbar: some View {
        HStack(spacing: 24) {
            Menu {
                Button("generate.algorithm.ed25519") { model.beginGenerate(algorithm: .ed25519) }
                    .accessibilityIdentifier("contentview.generate-ed25519")
                Button("generate.algorithm.rsa") { model.beginGenerate(algorithm: .rsa) }
                    .accessibilityIdentifier("contentview.generate-rsa")
                Button("generate.algorithm.ecdsa") { model.beginGenerate(algorithm: .ecdsa) }
                    .accessibilityIdentifier("contentview.generate-ecdsa")
            } label: {
                Image(systemName: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .help("toolbar.generate.help")
            .accessibilityIdentifier("contentview.generate-menu")
            .accessibilityLabel("toolbar.generate.help")

            Menu {
                Button("import.fromClipboard") { model.importFromPasteboard() }
                    .accessibilityIdentifier("contentview.import-clipboard")
                Button("import.fromFile") { model.importFromFile() }
                    .accessibilityIdentifier("contentview.import-file")
                if model.selectedTab == .recipients {
                    Button("import.fromKeyserver") {
                        model.showFetchSheet = true
                    }
                    .accessibilityIdentifier("contentview.import-keyserver")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .help("toolbar.import.help")
            .accessibilityIdentifier("contentview.import-menu")
            .accessibilityLabel("toolbar.import.help")

            Button {
                model.exportSelectedPublicToPasteboard()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedKey == nil)
            .help("toolbar.export.help")
            .accessibilityIdentifier("contentview.export-button")
            .accessibilityLabel("toolbar.export.help")

            Button {
                model.showDetailSheet = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedKey == nil)
            .help("toolbar.details.help")
            .accessibilityIdentifier("contentview.details-button")
            .accessibilityLabel("toolbar.details.help")

            Button {
                model.showDeleteConfirmation = true
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedKey == nil)
            .help("toolbar.delete.help")
            .accessibilityIdentifier("contentview.delete-button")
            .accessibilityLabel("toolbar.delete.help")
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
                model.rotateMessage = "rotate.encryption.message"
                model.showRotateSheet = true
            },
            onRotateSigning: {
                model.showDetailSheet = false
                model.rotateMessage = "rotate.signing.message"
                model.showRotateSheet = true
            },
            onPublish: {
                model.showDetailSheet = false
                model.publishMessage = "publish.uploading"
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
        let format = first.isExpired ? "banner.expired" : "banner.expiringSoon"
        let label = String(format: format.localized, first.userID + suffix)
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
        let label = String(format: "banner.trustConflict".localized, first.email + suffix)
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                Text(label)
                    .font(.callout)
                Spacer()
            }
            .foregroundStyle(.orange)
            .padding(.horizontal)
            .accessibilityIdentifier("contentview.trust-conflict-banner")
        )
    }

    private var extendExpirySheet: some View {
        VStack(spacing: 16) {
            Text("extendExpiry.title")
                .font(.headline)
            DatePicker(
                "extendExpiry.dateLabel",
                selection: $model.extendExpiryDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .accessibilityIdentifier("contentview.extendexpiry.datepicker")
            HStack(spacing: 12) {
                Button("button.cancel") { model.showExtendExpirySheet = false }
                    .accessibilityIdentifier("contentview.extendexpiry.cancel")
                Button("button.extend") {
                    model.showExtendExpirySheet = false
                    model.extendSelectedExpiry()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("contentview.extendexpiry.extend")
            }
        }
        .padding()
        .frame(width: 400)
    }

    private var revokeConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("revoke.title")
                .font(.headline)
            Text("revoke.message")
                .font(.callout)
            TextField("revoke.fingerprint.placeholder", text: $model.revokeFingerprintInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.revoke.fingerprint")
            TextField("revoke.reason.placeholder", text: $model.revokeReason)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.revoke.reason")
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") { model.showRevokeConfirmation = false }
                    .accessibilityIdentifier("contentview.revoke.cancel")
                Button("button.revoke", role: .destructive) {
                    model.showRevokeConfirmation = false
                    model.revokeSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.revokeFingerprintInput.isEmpty)
                .accessibilityIdentifier("contentview.revoke.confirm")
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var rotateConfirmationSheet: some View {
        VStack(spacing: 16) {
            Text("rotate.title")
                .font(.headline)
            Text(model.rotateMessage.localized)
                .font(.callout)
            HStack(spacing: 12) {
                Button("button.cancel") { model.showRotateSheet = false }
                    .accessibilityIdentifier("contentview.rotate.cancel")
                Button("button.rotate") {
                    model.showRotateSheet = false
                    if model.rotateMessage == "rotate.encryption.message" {
                        model.rotateEncryptionSubkey()
                    } else {
                        model.rotateSigningSubkey()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("contentview.rotate.confirm")
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var publishSheet: some View {
        VStack(spacing: 16) {
            Text("publish.title")
                .font(.headline)
            Text(model.publishMessage.localized)
                .font(.callout)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("button.ok") { model.showPublishSheet = false }
                    .accessibilityIdentifier("contentview.publish.ok")
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var fetchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("fetch.title")
                .font(.headline)
            Text("fetch.message")
                .font(.callout)
            TextField("fetch.query.placeholder", text: $model.fetchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .accessibilityIdentifier("contentview.fetch.query")

            if let key = model.fetchedKey {
                Text(String(format: "fetch.found".localized, key.source))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") {
                    model.showFetchSheet = false
                    model.fetchQuery = ""
                    model.fetchedKey = nil
                }
                .accessibilityIdentifier("contentview.fetch.cancel")
                Button("button.search") {
                    model.discoverKey()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.fetchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("contentview.fetch.search")
                if model.fetchedKey != nil {
                    Button("button.import") {
                        model.importFetchedKey()
                    }
                    .accessibilityIdentifier("contentview.fetch.import")
                }
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var clipboardImportSheet: some View {
        VStack(spacing: 16) {
            Text("clipboardImport.title")
                .font(.headline)
            Text("clipboardImport.message")
                .font(.callout)
            HStack(spacing: 12) {
                Button("button.cancel") {
                    model.showClipboardImport = false
                    model.clipboardText = ""
                }
                .accessibilityIdentifier("contentview.clipboard.cancel")
                Button("button.import") {
                    model.confirmClipboardImport()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("contentview.clipboard.import")
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
            Text(String(format: "generateKey.sheet.title".localized, algorithm.rawValue))
                .font(.headline)
            Text("generateKey.userIDLabel")
                .font(.callout)
            TextField("generateKey.userIDPlaceholder", text: $userID)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .accessibilityIdentifier("contentview.generate.userid")
            HStack {
                Spacer()
                Button("button.cancel") { dismiss() }
                    .accessibilityIdentifier("contentview.generate.cancel")
                Button("button.generate") {
                    onGenerate(userID, algorithm)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(userID.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("contentview.generate.confirm")
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
