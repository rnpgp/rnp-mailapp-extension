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

    var body: some View {
        rootContent
            .frame(minWidth: 760, minHeight: 480)
            .toolbar { toolbarItems }
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
                    },
                    onImportFromKeyring: {
                        model.showOnboarding = false
                        model.currentSheet = .importFromKeyring
                    }
                )
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
            .sheet(isPresented: $model.showMailExtensionSetup) {
                MailExtensionEnableView(model: model)
            }
            .sheet(item: $model.currentSheet) { sheet in
                sheetView(for: sheet)
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
            .onChange(of: model.manager.keys, initial: false) { _, _ in
                if let fingerprint = model.pendingReviewFingerprint {
                    model.openReview(fingerprint: fingerprint)
                }
            }
    }

    @ViewBuilder
    private func sheetView(for sheet: Sheet) -> some View {
        switch sheet {
        case .generate:
            GenerateKeySheet(algorithm: model.generateAlgorithm) { userID, algorithm in
                model.generate(userID: userID, algorithm: algorithm)
            }
        case .detail:
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
        case .clipboardImport:   ClipboardImportSheet(model: model)
        case .extendExpiry:      ExtendExpirySheet(model: model)
        case .revoke:            RevokeSheet(model: model)
        case .rotate(let kind):  RotateSheet(model: model, kind: kind)
        case .publish:           PublishSheet(model: model)
        case .fetch:             FetchSheet(model: model)
        case .foreignPassphrase: ForeignPassphraseSheet(model: model)
        case .trustHistory:
            TrustHistoryView(email: model.trustHistoryEmail, records: model.trustHistoryRecords)
                .frame(minWidth: 520, minHeight: 420)
        case .keyringUnlock:     KeyringUnlockSheet(model: model)
        case .licenses:
            LicensesView(sourcesMarkdown: LicensesView.loadSources())
        case .keyServerSettings:
            KeyServerSettingsView()
                .frame(minWidth: 480, minHeight: 420)
        case .securitySettings:  SecuritySettingsSheet(model: model)
        case .importFromKeyring: ImportFromKeyringSheet(model: model)
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
        .rnpAnimation(value: model.trustConflicts.count)
        .rnpAnimation(value: model.expiryReport().count)
        .rnpAnimation(value: model.importError)
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
            // Return opens the detail sheet for the selected key.
            // ⌘F focusing the search field requires modifying RnpSearchField
            // in swift-rnp — deferred.
            .background {
                Button("shortcut.detail") { if model.selectedKey != nil { model.currentSheet = .detail } }
                    .keyboardShortcut(.return, modifiers: [])
                    .hidden()
            }
            bannerStack
                .padding(.horizontal, RnpSpacing.sm)
            sectionHeader
                .padding(.horizontal, RnpSpacing.md)
                .padding(.top, RnpSpacing.xxs)
            keyList
            if !model.manager.archivedKeys.isEmpty {
                Divider()
                ArchivedKeysSection(viewModel: ArchivedKeysViewModel(
                    keyManager: nil,
                    onRestore: { fpr in
                        try? model.manager.restoreArchivedKey(fingerprint: fpr)
                    },
                    onDeleteForever: { fpr in
                        model.manager.deleteKeyForever(fingerprint: fpr)
                    }
                ))
                .padding(.horizontal, RnpSpacing.sm)
                .padding(.bottom, RnpSpacing.xs)
            }
            Divider()
            NavigationLink {
                FileToolsView(model: model)
                    .navigationTitle("fileTools.windowTitle")
            } label: {
                Label("nav.fileTools", systemImage: "lock.doc")
                    .padding(.horizontal, RnpSpacing.sm)
                    .padding(.vertical, RnpSpacing.xs)
            }
            .accessibilityIdentifier("contentview.file-tools-link")
            NavigationLink {
                RoadmapNavigationCoordinator()
                    .navigationTitle("title.tools")
            } label: {
                Label("nav.tools", systemImage: "wrench.and.screwdriver")
                    .padding(.horizontal, RnpSpacing.sm)
                    .padding(.vertical, RnpSpacing.xs)
            }
            .accessibilityIdentifier("contentview.tools-link")
        }
        .rnpAnimation(value: model.trustConflicts.count)
        .rnpAnimation(value: model.expiryReport().count)
        .rnpAnimation(value: model.importError)
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
        .rnpAnimation(value: model.selection)
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
        // Keyboard shortcuts: ⌘1 = My Keys, ⌘2 = Recipients. Hidden
        // buttons are the standard SwiftUI pattern for global shortcuts
        // that don't belong to a specific control.
        .background {
            Group {
                Button("tab.myKeys") { model.selectedTab = .myKeys }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("tab.recipients") { model.selectedTab = .recipients }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
            }
        }
        .accessibilityHint("shortcut.tab.hint")
    }

    private var keyList: some View {
        KeysListView(
            keys: model.filteredKeys,
            selection: $model.selection,
            trustState: { key in
                key.hasSecret ? nil : model.trustState(for: key)
            },
            onDoubleTap: { _ in model.currentSheet = .detail },
            onExport: { key in model.exportPublicToPasteboard(key) },
            onCopyFingerprint: { key in model.copyFingerprint(key) },
            onDelete: { key in model.confirmDelete(key) },
            onRefresh: { model.refresh() }
        )
        .overlay { emptyStateOverlay }
        .rnpAnimation(value: model.filteredKeys)
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
                            model.currentSheet = .fetch
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

    private func detailActions(for key: KeyInfo) -> KeyDetailActions {
        KeyDetailActions(
            onExportPublic: { model.exportSelectedPublicToPasteboard() },
            onExportSecret: { model.exportSelectedSecretToPasteboard() },
            onDelete: {
                model.currentSheet = nil
                model.showDeleteConfirmation = true
            },
            onExtendExpiry: {
                model.currentSheet = .extendExpiry
            },
            onRevoke: {
                model.currentSheet = .revoke
            },
            onRotateEncryption: {
                model.currentSheet = .rotate(kind: .encryption)
            },
            onRotateSigning: {
                model.currentSheet = .rotate(kind: .signing)
            },
            onPublish: {
                model.publishMessage = "publish.uploading"
                model.currentSheet = .publish
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


}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: ContentViewModel(manager: KeysManager()))
    }
}
#endif
