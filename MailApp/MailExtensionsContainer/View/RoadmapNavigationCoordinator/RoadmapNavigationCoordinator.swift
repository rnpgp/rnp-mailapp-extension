//
//  RoadmapNavigationCoordinator.swift
//  RNP
//
//  Tools hub for the container app. Surfaces the swift-rnp library's
//  tool views (Key Health, Encryption settings, Per-account Autocrypt,
//  Mailbox scan, Recovery wizard, Key transition wizard) as a polished
//  card-based hub rather than a debug-style list of buttons.
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
        ScrollView {
            VStack(alignment: .leading, spacing: RnpSpacing.xl) {
                header
                ToolSectionView(label: "Inspect", tools: inspectTools)
                ToolSectionView(label: "Configure", tools: configureTools)
                if recoveryTools.isEmpty {
                    emptyRecoverSection
                } else {
                    ToolSectionView(label: "Recover", tools: recoveryTools)
                }
                ToolSectionView(label: "Discover", tools: discoverTools)
            }
            .padding(.horizontal, RnpSpacing.xl)
            .padding(.top, RnpSpacing.lg)
            .padding(.bottom, RnpSpacing.xxl)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("title.tools")
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

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            if let fingerprint = firstKeyFingerprint {
                Text(fingerprint)
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Your primary key fingerprint")
            }
            Text("Tools")
                .font(.largeTitle.weight(.semibold))
            Text("Keep your OpenPGP keyring healthy, private, and recoverable.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tool groups

    private var inspectTools: [Tool] {
        [
            Tool(
                title: "Check key health",
                description: "See expiration, strength, and revocation state at a glance.",
                systemImage: "heart.text.square",
                identifier: "nav.key-health",
                action: { presentedSheet = .keyHealth }
            )
        ]
    }

    private var configureTools: [Tool] {
        [
            Tool(
                title: "Configure encryption defaults",
                description: "Set default sign and encrypt behavior for new messages.",
                systemImage: "lock.shield",
                identifier: "nav.encryption-settings",
                action: { presentedSheet = .encryptionSettings }
            ),
            Tool(
                title: "Manage Autocrypt per account",
                description: "Override Autocrypt send-policy for individual mailboxes.",
                systemImage: "at",
                identifier: "nav.account-autocrypt",
                action: { presentedSheet = .accountAutocrypt }
            )
        ]
    }

    private var recoveryTools: [Tool] {
        guard let firstSecret = firstSecretOwnKey() else { return [] }
        return [
            Tool(
                title: "Save recovery materials",
                description: "Export a paper key and revocation certificate for offline storage.",
                systemImage: "lifepreserver",
                identifier: "nav.recovery-wizard",
                action: { presentedSheet = .recoveryWizard(fingerprint: firstSecret.fingerprint) }
            ),
            Tool(
                title: "Move to a new key",
                description: "Generate a fresh primary key and migrate your identity to it.",
                systemImage: "arrow.triangle.2.circlepath",
                identifier: "nav.transition-wizard",
                action: {
                    presentedSheet = .transitionWizard(
                        fingerprint: firstSecret.fingerprint,
                        primaryUserID: firstSecret.primaryUserID
                    )
                }
            )
        ]
    }

    private var discoverTools: [Tool] {
        [
            Tool(
                title: "Encrypt & decrypt files",
                description: "Click \"Files\" in the sidebar to drop a file and encrypt it for people in your keyring.",
                systemImage: "lock.doc",
                identifier: "nav.file-tools",
                action: {
                    // Hint: user should click "Files" in the sidebar.
                    // The Tools hub is itself in the detail column, so we
                    // can't navigate from here; the sidebar is the entry.
                }
            ),
            Tool(
                title: "Scan mailbox for keys",
                description: "Find public keys in received mail and decide which to import.",
                systemImage: "envelope.open.badge",
                identifier: "nav.mailbox-scan",
                action: { presentedSheet = .mailboxScanConsent }
            )
        ]
    }

    @ViewBuilder
    private var emptyRecoverSection: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.sm) {
            sectionHeader("Recover")
            HStack(spacing: RnpSpacing.md) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text("Generate or import a secret key to enable recovery tools.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(RnpSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            )
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .padding(.leading, RnpSpacing.xxs)
    }

    private var firstKeyFingerprint: String? {
        guard let engine,
              let keys = try? engine.keyManager.listKeys(),
              let first = keys.first else { return nil }
        return first.fingerprint.groupedFingerprintBlocks
    }

    private func firstSecretOwnKey() -> KeyInfo? {
        guard let engine else { return nil }
        return (try? engine.keyManager.listKeys())?.first(where: { $0.hasSecret })
    }
}

// MARK: - Tool model

private struct Tool: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
    let identifier: String
    let action: () -> Void
}

// MARK: - Section

private struct ToolSectionView: View {
    let label: String
    let tools: [Tool]

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.sm) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.leading, RnpSpacing.xxs)
            VStack(spacing: RnpSpacing.xs) {
                ForEach(tools) { tool in
                    ToolCard(tool: tool)
                }
            }
        }
    }
}

// MARK: - Card

private struct ToolCard: View {
    let tool: Tool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: tool.action) {
            HStack(spacing: RnpSpacing.md) {
                iconTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(RnpSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                    .fill(isHovering
                          ? Color.accentColor.opacity(0.07)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                    .strokeBorder(
                        isHovering
                        ? Color.accentColor.opacity(0.35)
                        : Color(nsColor: .separatorColor),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 && isEnabled }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(tool.identifier)
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
            Image(systemName: tool.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 32, height: 32)
    }
}
