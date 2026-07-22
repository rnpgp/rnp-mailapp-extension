//
//  ContentView.swift
//  RNP
//
//  Key manager window: a native split view (key list beside the selected
//  key's details) with a toolbar holding the primary actions. On macOS 12
//  the window falls back to a single-column layout and presents details in
//  a sheet instead.
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
    @State private var showKeyServerSettings = false

    var body: some View {
        rootContent
            .frame(minWidth: 760, minHeight: 480)
            .toolbar { toolbarItems }
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
                        hasPendingKeyChange: model.hasPendingKeyChange(for: key),
                        actions: detailActions(for: key)
                    )
                    .frame(minWidth: 560, minHeight: 520)
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
            .sheet(isPresented: Binding(
                get: { model.foreignPassphraseRequest != nil },
                set: { isPresented in
                    // Dismissing the prompt without unlocking (Escape)
                    // behaves like Skip.
                    if !isPresented, let request = model.foreignPassphraseRequest {
                        model.skipForeignPassphrase(request)
                    }
                }
            )) {
                ForeignPassphraseSheet(model: model)
            }
            .sheet(isPresented: $model.showTrustHistorySheet) {
                TrustHistoryView(email: model.trustHistoryEmail, records: model.trustHistoryRecords)
                    .frame(minWidth: 520, minHeight: 420)
            }
            .sheet(isPresented: $model.showKeyringUnlockSheet) {
                KeyringUnlockSheet(model: model)
            }
            .sheet(isPresented: $showLicenses) {
                LicensesView(sourcesMarkdown: LicensesView.loadSources())
            }
            .sheet(isPresented: $showKeyServerSettings) {
                KeyServerSettingsView()
                    .frame(minWidth: 480, minHeight: 420)
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
            .onReceive(NotificationCenter.default.publisher(for: .showKeyServerSettings)) { _ in
                showKeyServerSettings = true
            }
            .onOpenURL { url in
                guard url.scheme == "rnpmail" else {
                    return
                }
                switch url.host {
                case "review":
                    guard let fingerprint = url.pathComponents.dropFirst().first,
                          !fingerprint.isEmpty
                    else {
                        return
                    }
                    model.openReview(fingerprint: fingerprint)
                case "fetch":
                    guard let email = url.pathComponents.dropFirst().first,
                          !email.isEmpty
                    else {
                        return
                    }
                    model.openFetch(email: email.removingPercentEncoding ?? email)
                default:
                    return
                }
            }
            .onChange(of: model.manager.keys) { _ in
                if let fingerprint = model.pendingReviewFingerprint {
                    model.openReview(fingerprint: fingerprint)
                }
            }
    }

    // MARK: - Layout

    @ViewBuilder
    private var rootContent: some View {
        if #available(macOS 13.0, *) {
            splitContent
        } else {
            stackContent
        }
    }

    /// macOS 13+: key list in the leading column, selected key's details in
    /// the detail column.
    @available(macOS 13.0, *)
    private var splitContent: some View {
        NavigationSplitView {
            listColumn
                .navigationTitle(Text("title.keysManager"))
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
        } detail: {
            detailColumn
        }
    }

    /// macOS 12 fallback: single-column list; details open in a sheet.
    private var stackContent: some View {
        VStack(spacing: RnpSpacing.sm) {
            tabPicker
            RnpSearchField(
                text: $model.searchText,
                prompt: "search.prompt".localized,
                accessibilityIdentifier: "contentview.search-field"
            )
            bannerStack
            sectionHeader
            keyList
        }
        .padding()
        .animation(.default, value: model.trustConflicts.count)
        .animation(.default, value: model.expiryReport().count)
        .animation(.default, value: model.importError)
        .navigationTitle(Text("title.keysManager"))
    }

    private var listColumn: some View {
        VStack(spacing: RnpSpacing.xs) {
            tabPicker
                .padding(.horizontal, RnpSpacing.sm)
                .padding(.top, RnpSpacing.sm - 2)
            RnpSearchField(
                text: $model.searchText,
                prompt: "search.prompt".localized,
                accessibilityIdentifier: "contentview.search-field"
            )
            .padding(.horizontal, RnpSpacing.sm)
            bannerStack
                .padding(.horizontal, RnpSpacing.sm)
            sectionHeader
                .padding(.horizontal, RnpSpacing.md)
                .padding(.top, RnpSpacing.xxs)
            keyList
        }
        .animation(.default, value: model.trustConflicts.count)
        .animation(.default, value: model.expiryReport().count)
        .animation(.default, value: model.importError)
    }

    /// "MY KEYS — 3" style header above the list.
    private var sectionHeader: some View {
        RnpSectionHeader(
            title: model.selectedTab.localizedName,
            count: model.filteredKeys.count
        )
    }

    private var detailColumn: some View {
        Group {
            if let key = model.selectedKey {
                KeyDetailView(
                    key: key,
                    subkeys: model.manager.subkeys(for: key),
                    isRecipient: model.selectedTab == .recipients,
                    trustState: model.trustState(for: key),
                    hasPendingKeyChange: model.hasPendingKeyChange(for: key),
                    actions: detailActions(for: key),
                    identifierPrefix: "keydetail.pane"
                )
                .id(key.fingerprint)
                .transition(.opacity)
            } else {
                noSelectionPlaceholder
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionPlaceholder: some View {
        VStack(spacing: RnpSpacing.md) {
            Image(systemName: "key.fill")
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("detail.noSelection")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("detail.noSelection.hint")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Key list

    private var tabPicker: some View {
        Picker("tab.selector", selection: $model.selectedTab) {
            ForEach(KeyTab.allCases, id: \.self) { tab in
                Text(tab.localizedName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("contentview.tab-picker")
    }

    private var keyList: some View {
        KeysListView(
            keys: model.filteredKeys,
            selection: $model.selection,
            trustState: { key in
                key.hasSecret ? nil : model.trustState(for: key)
            },
            onDoubleTap: { _ in model.showDetailSheet = true },
            onExport: { key in model.exportPublicToPasteboard(key) },
            onCopyFingerprint: { key in model.copyFingerprint(key) },
            onDelete: { key in model.confirmDelete(key) },
            onRefresh: { model.refresh() }
        )
        .overlay { emptyStateOverlay }
        .animation(.default, value: model.filteredKeys)
        .onDrop(of: [.fileURL, .data, .plainText], isTargeted: .constant(false)) { providers in
            handleDrop(providers: providers)
        }
    }

    @ViewBuilder
    private var emptyStateOverlay: some View {
        if model.isSearchEmpty {
            RnpEmptyState(
                icon: "magnifyingglass",
                title: "emptyState.search.title",
                message: String(format: "emptyState.search.message".localized, model.searchText)
            ) {
                Button("emptyState.search.clear") { model.searchText = "" }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("contentview.empty.clearsearch")
            }
            .transition(.opacity)
        } else if model.keys.isEmpty {
            if model.selectedTab == .myKeys {
                RnpEmptyState(
                    icon: "key.fill",
                    title: "emptyState.title",
                    message: "emptyState.message".localized
                ) {
                    HStack(spacing: RnpSpacing.sm) {
                        Button("emptyState.generate") {
                            model.beginGenerate(algorithm: .ed25519)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("contentview.empty.generate")
                        Button("emptyState.import") {
                            model.importFromFile()
                        }
                        .accessibilityIdentifier("contentview.empty.import")
                    }
                    .controlSize(.large)
                }
                .transition(.opacity)
            } else {
                RnpEmptyState(
                    icon: "person.2",
                    title: "emptyState.recipients.title",
                    message: "emptyState.recipients.message".localized
                ) {
                    HStack(spacing: RnpSpacing.sm) {
                        Button("emptyState.recipients.fetch") {
                            model.showFetchSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("contentview.empty.fetch")
                        Button("emptyState.import") {
                            model.importFromFile()
                        }
                        .accessibilityIdentifier("contentview.empty.import")
                    }
                    .controlSize(.large)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("generate.algorithm.ed25519") { model.beginGenerate(algorithm: .ed25519) }
                    .accessibilityIdentifier("contentview.generate-ed25519")
                Button("generate.algorithm.rsa") { model.beginGenerate(algorithm: .rsa) }
                    .accessibilityIdentifier("contentview.generate-rsa")
                Button("generate.algorithm.ecdsa") { model.beginGenerate(algorithm: .ecdsa) }
                    .accessibilityIdentifier("contentview.generate-ecdsa")
            } label: {
                Label("toolbar.generate.help", systemImage: "plus")
            }
            .menuIndicator(.hidden)
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
                Label("toolbar.import.help", systemImage: "square.and.arrow.down")
            }
            .menuIndicator(.hidden)
            .help("toolbar.import.help")
            .accessibilityIdentifier("contentview.import-menu")
            .accessibilityLabel("toolbar.import.help")

            Button {
                model.exportSelectedPublicToPasteboard()
            } label: {
                Label("toolbar.export.help", systemImage: "square.and.arrow.up")
            }
            .disabled(model.selectedKey == nil)
            .help("toolbar.export.help")
            .accessibilityIdentifier("contentview.export-button")
            .accessibilityLabel("toolbar.export.help")

            Button {
                model.showDetailSheet = true
            } label: {
                Label("toolbar.details.help", systemImage: "info.circle")
            }
            .disabled(model.selectedKey == nil)
            .help("toolbar.details.help")
            .accessibilityIdentifier("contentview.details-button")
            .accessibilityLabel("toolbar.details.help")

            Button {
                model.showDeleteConfirmation = true
            } label: {
                Label("toolbar.delete.help", systemImage: "trash")
            }
            .disabled(model.selectedKey == nil)
            .help("toolbar.delete.help")
            .accessibilityIdentifier("contentview.delete-button")
            .accessibilityLabel("toolbar.delete.help")

            Button {
                model.refresh()
            } label: {
                Label("toolbar.refresh.help", systemImage: "arrow.clockwise")
            }
            .help("toolbar.refresh.help")
            .accessibilityIdentifier("contentview.refresh-button")
            .accessibilityLabel("toolbar.refresh.help")
        }
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
            },
            onRejectNewKey: {
                model.rejectKeyChange(for: key)
            },
            onShowTrustHistory: {
                model.openTrustHistory(for: key)
            }
        )
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannerStack: some View {
        let conflicts = model.trustConflicts
        let expiry = model.expiryReport()
        if model.keyringLocked || !conflicts.isEmpty || !expiry.isEmpty || model.importError != nil {
            VStack(spacing: RnpSpacing.xs) {
                if model.keyringLocked {
                    BannerView(
                        icon: "lock.fill",
                        tint: RnpBrand.critical,
                        text: "banner.keyringLocked".localized,
                        actionTitle: "banner.keyringLocked.unlock",
                        action: { model.showKeyringUnlockSheet = true },
                        actionIdentifier: "contentview.keyring-locked.unlock"
                    )
                    .accessibilityIdentifier("contentview.keyring-locked-banner")
                }
                if let importError = model.importError {
                    RnpInlineError(
                        message: importError,
                        recoverySuggestion: "error.importFailed.recovery".localized,
                        onDismiss: { model.importError = nil }
                    )
                    .accessibilityIdentifier("contentview.import-error")
                }
                if let first = conflicts.first {
                    let suffix = conflicts.count > 1 ? " (and \(conflicts.count - 1) more)" : ""
                    BannerView(
                        icon: "exclamationmark.shield.fill",
                        tint: RnpBrand.critical,
                        text: String(format: "banner.trustConflict".localized, first.email + suffix),
                        actionTitle: "detail.keepOldBinding",
                        action: { model.rejectConflict(first) },
                        actionIdentifier: "contentview.trust-conflict-keep-old"
                    )
                    .accessibilityIdentifier("contentview.trust-conflict-banner")
                }
                if let first = expiry.first {
                    let suffix = expiry.count > 1 ? " (and \(expiry.count - 1) more)" : ""
                    let format = first.isExpired ? "banner.expired" : "banner.expiringSoon"
                    BannerView(
                        icon: first.isExpired ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                        tint: first.isExpired ? RnpBrand.critical : RnpBrand.unverified,
                        text: String(format: format.localized, first.userID + suffix)
                    )
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Sheets

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
                Spacer()
                Button("button.cancel") { model.showExtendExpirySheet = false }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("contentview.extendexpiry.cancel")
                Button("button.extend") {
                    model.showExtendExpirySheet = false
                    model.extendSelectedExpiry()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("contentview.extendexpiry.extend")
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var revokeConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("revoke.title")
                .font(.headline)
            Text("revoke.message")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("revoke.fingerprint.placeholder", text: $model.revokeFingerprintInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.revoke.fingerprint")
            TextField("revoke.reason.placeholder", text: $model.revokeReason)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.revoke.reason")
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") { model.showRevokeConfirmation = false }
                    .keyboardShortcut(.cancelAction)
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
        .padding(20)
        .frame(width: 420)
    }

    private var rotateConfirmationSheet: some View {
        VStack(spacing: 16) {
            Text("rotate.title")
                .font(.headline)
            Text(model.rotateMessage.localized)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") { model.showRotateSheet = false }
                    .keyboardShortcut(.cancelAction)
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
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("contentview.rotate.confirm")
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var publishSheet: some View {
        VStack(spacing: 16) {
            Text("publish.title")
                .font(.headline)
            HStack(spacing: 10) {
                if model.isPublishing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.publishMessage.localized)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("button.ok") { model.showPublishSheet = false }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isPublishing)
                    .accessibilityIdentifier("contentview.publish.ok")
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var fetchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("fetch.title")
                .font(.headline)
            Text("fetch.message")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("fetch.query.placeholder", text: $model.fetchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .accessibilityIdentifier("contentview.fetch.query")

            Toggle(isOn: Binding(
                get: { model.autoFetchRecipientKeys },
                set: { model.autoFetchRecipientKeys = $0 }
            )) {
                Text("fetch.autoFetch")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("contentview.fetch.autofetch")

            if model.isDiscoveringKey {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("fetch.searching")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("contentview.fetch.progress")
            } else if let key = model.fetchedKey {
                Label(String(format: "fetch.found".localized, key.source), systemImage: "checkmark.circle.fill")
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
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("contentview.fetch.cancel")
                Button("button.search") {
                    model.discoverKey()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.fetchQuery.trimmingCharacters(in: .whitespaces).isEmpty || model.isDiscoveringKey)
                .accessibilityIdentifier("contentview.fetch.search")
                if model.fetchedKey != nil {
                    Button("button.import") {
                        model.importFetchedKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("contentview.fetch.import")
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var clipboardImportSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("clipboardImport.title")
                .font(.headline)
            Text("clipboardImport.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") {
                    model.showClipboardImport = false
                    model.clipboardText = ""
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("contentview.clipboard.cancel")
                Button("button.import") {
                    model.confirmClipboardImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("contentview.clipboard.import")
            }
        }
        .padding(20)
        .frame(width: 380)
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

/// Tinted banner used for trust-conflict and expiry warnings.
private struct BannerView: View {
    let icon: String
    let tint: Color
    let text: String
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var actionIdentifier: String? = nil

    var body: some View {
        HStack(spacing: RnpSpacing.xs) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                if let actionIdentifier {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(actionIdentifier)
                } else {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, RnpSpacing.sm)
        .padding(.vertical, RnpSpacing.xs)
        .background(
            tint.opacity(0.1),
            in: RoundedRectangle(cornerRadius: RnpRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RnpRadius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        // Keep the action button individually accessible when present.
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

/// Sheet collecting the user ID for a new key.
private struct GenerateKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userID = ""

    let algorithm: KeyAlgorithm
    let onGenerate: (String, KeyAlgorithm) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: "generateKey.sheet.title".localized, algorithm.rawValue))
                .font(.headline)
            Text("generateKey.userIDLabel")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("generateKey.userIDPlaceholder", text: $userID)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .accessibilityIdentifier("contentview.generate.userid")
            HStack {
                Spacer()
                Button("button.cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("contentview.generate.cancel")
                Button("button.generate") {
                    onGenerate(userID, algorithm)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(userID.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("contentview.generate.confirm")
            }
        }
        .padding(20)
    }
}

/// Sheet asking for the passphrase of an imported secret key that is
/// protected by a foreign passphrase (different from the keyring
/// passphrase). Reads the pending request from the model so queued requests
/// re-render in place.
private struct ForeignPassphraseSheet: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        Group {
            if let request = model.foreignPassphraseRequest {
                ForeignPassphraseForm(model: model, request: request)
                    // Reset the form state when the next queued key shows.
                    .id(request.fingerprint)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Form of the foreign passphrase sheet: shows the key's user ID and
/// fingerprint; the user can store the passphrase in the Keychain or
/// re-protect the key with the keyring passphrase.
private struct ForeignPassphraseForm: View {
    @ObservedObject var model: ContentViewModel
    let request: LockedSecretKeyInfo
    @State private var passphrase = ""
    @State private var reprotect = false
    @State private var showWrongPassphrase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("foreignPassphrase.title")
                .font(.headline)
            Text("foreignPassphrase.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.primaryUserID)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(request.fingerprint.groupedFingerprintBlocks)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("contentview.foreignpassphrase.keyinfo")
            SecureField("foreignPassphrase.fieldLabel", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.foreignpassphrase.field")
            Toggle(isOn: $reprotect) {
                Text("foreignPassphrase.reprotect")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("contentview.foreignpassphrase.reprotect")
            if showWrongPassphrase {
                Text("foreignPassphrase.wrong")
                    .font(.callout)
                    .foregroundStyle(Color.red)
                    .accessibilityIdentifier("contentview.foreignpassphrase.wrong")
            }
            HStack {
                Spacer()
                Button("button.skip") {
                    model.skipForeignPassphrase(request)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("contentview.foreignpassphrase.skip")
                Button("foreignPassphrase.unlock") {
                    showWrongPassphrase = !model.resolveForeignPassphrase(
                        request,
                        passphrase: passphrase,
                        reprotectWithKeyringPassphrase: reprotect
                    )
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(passphrase.isEmpty)
                .accessibilityIdentifier("contentview.foreignpassphrase.unlock")
            }
        }
    }
}

/// Sheet unlocking a Touch ID-protected keyring: primary Touch ID button,
/// with manual keyring-passphrase entry as the fallback when Touch ID fails
/// or was cancelled. Dismisses itself once the keyring is unlocked.
private struct KeyringUnlockSheet: View {
    @ObservedObject var model: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var showWrongPassphrase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("keyringUnlock.title")
                .font(.headline)
            Text("keyringUnlock.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("keyringUnlock.touchID") {
                model.unlockKeyringWithTouchID()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("contentview.keyringunlock.touchid")
            Divider()
            SecureField("keyringUnlock.fieldLabel", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("contentview.keyringunlock.field")
            if showWrongPassphrase {
                Text("keyringUnlock.wrong")
                    .font(.callout)
                    .foregroundStyle(Color.red)
                    .accessibilityIdentifier("contentview.keyringunlock.wrong")
            }
            HStack {
                Spacer()
                Button("button.cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("contentview.keyringunlock.cancel")
                Button("keyringUnlock.unlock") {
                    showWrongPassphrase = !model.unlockKeyringManually(passphrase)
                    if !showWrongPassphrase {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(passphrase.isEmpty)
                .accessibilityIdentifier("contentview.keyringunlock.unlock")
            }
        }
        .padding(20)
        .frame(width: 420)
        // Touch ID unlock is asynchronous; once the keyring opens (from
        // either path), close the sheet.
        .onChange(of: model.keyringLocked) { locked in
            if !locked {
                dismiss()
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: ContentViewModel(manager: KeysManager()))
    }
}
#endif
