//
//  RoadmapNavigationCoordinator.swift
//  RNP
//
//  Sketch for surfacing the roadmap SwiftUI views (KeyHealth,
//  RecoveryWizard, EncryptionSettings, MailboxScan) inside the
//  container app's NavigationView. Implemented as an additive view
//  that the container app's ContentView can present in a new
//  "Tools" tab or section without rewriting its existing layout.
//
//  All callbacks are wired through EngineEnvironment; the coordinator
//  only renders the views and bridges their action callbacks to the
//  underlying engine.
//

import SwiftUI
import Autocrypt
import KeyLifecycle
import MailSecurityEngine
import RnpMailUI

public struct RoadmapNavigationCoordinator: View {
    @Environment(\.engine) private var engine
    @State private var presentedSheet: Sheet?

    enum Sheet: Identifiable {
        case keyHealth
        case recoveryWizard(fingerprint: String)
        case encryptionSettings
        case accountAutocrypt
        case mailboxScan
        case mailboxScanConsent
        case transitionWizard(fingerprint: String, primaryUserID: String)

        var id: String {
            switch self {
            case .keyHealth: return "keyHealth"
            case let .recoveryWizard(fpr): return "recoveryWizard-\(fpr)"
            case .encryptionSettings: return "encryptionSettings"
            case .accountAutocrypt: return "accountAutocrypt"
            case .mailboxScan: return "mailboxScan"
            case .mailboxScanConsent: return "mailboxScanConsent"
            case let .transitionWizard(fpr, _): return "transitionWizard-\(fpr)"
            }
        }
    }

    public init() {}

    public var body: some View {
        List {
            Section("Tools") {
                Button {
                    presentedSheet = .keyHealth
                } label: {
                    Label("Key Health", systemImage: "heart.text.square")
                }
                .accessibilityIdentifier("nav.key-health")

                Button {
                    presentedSheet = .encryptionSettings
                } label: {
                    Label("Encryption settings", systemImage: "lock.shield")
                }
                .accessibilityIdentifier("nav.encryption-settings")

                Button {
                    presentedSheet = .accountAutocrypt
                } label: {
                    Label("Per-account Autocrypt", systemImage: "at")
                }
                .accessibilityIdentifier("nav.account-autocrypt")

                Button {
                    presentedSheet = .mailboxScanConsent
                } label: {
                    Label("Find keys in mailbox", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("nav.mailbox-scan")
            }

            if let firstSecret = firstSecretOwnKey() {
                Section("Recovery") {
                    Button {
                        presentedSheet = .recoveryWizard(fingerprint: firstSecret.fingerprint)
                    } label: {
                        Label("Save recovery materials", systemImage: "lifepreserver")
                    }
                    .accessibilityIdentifier("nav.recovery-wizard")

                    Button {
                        presentedSheet = .transitionWizard(
                            fingerprint: firstSecret.fingerprint,
                            primaryUserID: firstSecret.primaryUserID
                        )
                    } label: {
                        Label("Migrate to a new key", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("nav.transition-wizard")
                }
            }
        }
        .navigationTitle("Roadmap tools")
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .keyHealth:
                if let engine {
                    NavigationView {
                        KeyHealthView(viewModel: KeyHealthViewModel(keyManager: engine.keyManager))
                    }
                }
            case let .recoveryWizard(fpr):
                if let engine {
                    RecoverySheetWizard(viewModel: RecoverySheetViewModel(
                        keyFingerprint: fpr,
                        keyManager: engine.keyManager
                    ))
                }
            case .encryptionSettings:
                EncryptionSettingsView(viewModel: EncryptionSettingsViewModel(
                    storage: { _, _, _ in /* wire to UserDefaults */ }
                ))
            case .accountAutocrypt:
                // The AccountKeyedPolicyStore URL is the engine's
                // responsibility; the coordinator instantiates the
                // store in the engine's app-group container when one
                // is available. This is a sketch; the container app
                // wires the actual store via EngineEnvironment.
                let url = engine?.keyManager.directory
                    .appendingPathComponent("Autocrypt", isDirectory: true)
                    .appendingPathComponent("account-preferences.json")
                if let url, let store = try? AccountKeyedPolicyStore(storeURL: url) {
                    AccountAutocryptSettingsView(viewModel: AccountAutocryptSettingsViewModel(store: store))
                } else {
                    Text("Account Autocrypt settings unavailable (no engine).")
                        .padding()
                }
            case .mailboxScanConsent:
                MailboxScanConsentView(
                    onScan: { presentedSheet = .mailboxScan },
                    onSkip: { presentedSheet = nil }
                )
            case .mailboxScan:
                if let engine {
                    MailboxScanResultsView(viewModel: MailboxScanViewModel(engine: engine))
                }
            case let .transitionWizard(fpr, uid):
                if let engine {
                    KeyTransitionWizardSheet(viewModel: KeyTransitionWizardViewModel(
                        oldFingerprint: fpr,
                        oldPrimaryUserID: uid,
                        keyManager: engine.keyManager
                    ))
                }
            }
        }
    }

    private func firstSecretOwnKey() -> KeyInfo? {
        guard let engine else { return nil }
        return (try? engine.keyManager.listKeys())?.first(where: { $0.hasSecret })
    }
}

#Preview {
    RoadmapNavigationCoordinator()
        .engineEnvironment(nil)
}
