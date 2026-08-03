//
//  MailExtensionEnableView.swift
//  RNP
//
//  Walks the user through enabling "RNP for Mail" in macOS System Settings
//  → Privacy & Security → Extensions. macOS does not auto-grant Mail the
//  permission to load a freshly-installed MailExtension; the user has to
//  toggle it on themselves, and discovery of that toggle is poor. This view
//  makes the path obvious with a deep-link button.
//

import AppKit
import MailSecurityEngine
import RnpMailUI
import SwiftUI

/// Standalone sheet shown after onboarding (and re-openable from the Tools
/// hub banner). Wraps the steps + a deep-link to the right System Settings
/// pane. The model decides when to dismiss based on which button the user
/// tapped.
struct MailExtensionEnableView: View {
    @ObservedObject var model: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var didEnable = false

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.lg) {
            if didEnable {
                successState
            } else {
                header
                stepsList
                deepLinkButton
                    .padding(.top, RnpSpacing.xs)
                Divider()
                    .padding(.vertical, RnpSpacing.xxs)
                footerButtons
            }
        }
        .padding(RnpSpacing.xl)
        .frame(width: 520)
        .accessibilityIdentifier("mailextension.view")
    }

    private var successState: some View {
        VStack(spacing: RnpSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.green)
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("mailExtensionSetup.enabled.title")
                .font(.title3.weight(.semibold))
            Text("mailExtensionSetup.enabled.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            testMailButton
                .padding(.top, RnpSpacing.xs)
            Button("button.done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("mailextension.done")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var testMailButton: some View {
        if let mailtoURL = Self.buildTestMailURL(for: model) {
            Button {
                NSWorkspace.shared.open(mailtoURL)
            } label: {
                Label("mailExtensionSetup.testMail", systemImage: "envelope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("mailextension.test-mail")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xs) {
            HStack(spacing: RnpSpacing.sm) {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(RnpBrand.primary)
                    .font(.system(size: 28))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: RnpSpacing.xxs) {
                    Text("mailExtensionSetup.title")
                        .font(.title2.weight(.semibold))
                    Text("mailExtensionSetup.subtitle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.sm) {
            stepRow(number: 1, text: "mailExtensionSetup.step1")
            stepRow(number: 2, text: "mailExtensionSetup.step2")
            stepRow(number: 3, text: "mailExtensionSetup.step3")
        }
    }

    private func stepRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: RnpSpacing.sm) {
            ZStack {
                Circle()
                    .fill(RnpBrand.primary.opacity(0.15))
                Text("\(number)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(RnpBrand.primary)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deepLinkButton: some View {
        Button {
            MailExtensionSetup.openSystemSettingsExtensionsPane()
        } label: {
            Label("mailExtensionSetup.openButton", systemImage: "gear")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("mailextension.open-settings")
    }

    private var footerButtons: some View {
        HStack(spacing: RnpSpacing.sm) {
            Button("mailExtensionSetup.skip") {
                model.skipMailExtensionSetup()
                dismiss()
            }
            .accessibilityIdentifier("mailextension.skip")
            Spacer()
            Button("mailExtensionSetup.enabledButton") {
                model.markMailExtensionEnabled()
                didEnable = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("mailextension.enabled")
        }
    }

    /// Builds a `mailto:` URL prefilled with the user's primary email so
    /// they can send themselves a test encrypted mail. Returns nil if no
    /// secret key with a parseable email is found (the button just
    /// doesn't appear).
    static func buildTestMailURL(for model: ContentViewModel) -> URL? {
        guard let primarySecret = model.manager.keys.first(where: { $0.hasSecret }) else {
            return nil
        }
        let candidate = primarySecret.primaryUserID.isEmpty
            ? (primarySecret.userIDs.first ?? "")
            : primarySecret.primaryUserID
        guard let ltIdx = candidate.lastIndex(of: "<"),
              let gtIdx = candidate.lastIndex(of: ">"),
              ltIdx < gtIdx else { return nil }
        let email = String(candidate[candidate.index(after: ltIdx)..<gtIdx])
        guard email.contains("@"), let atIdx = email.firstIndex(of: "@"),
              atIdx != email.startIndex, atIdx != email.index(before: email.endIndex) else {
            return nil
        }
        let subject = "RNP%20for%20Mail%20test"
        let body = "This%20message%20is%20a%20test%20of%20RNP%20for%20Mail.%0A%0AIn%20Mail%27s%20compose%20toolbar%2C%20toggle%20the%20lock%20icon%20to%20encrypt%20and%20the%20signature%20icon%20to%20sign%20before%20sending.%0A%0AWhen%20you%20receive%20this%20message%2C%20you%20should%20see%20the%20lock%20icon%20in%20the%20message%20list%20and%20the%20banner%20confirming%20encryption."
        guard let recipient = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "mailto:\(recipient)?subject=\(subject)&body=\(body)")
    }
}

/// Self-contained helper so the Tools hub banner can reuse the deep-link
/// without rebuilding SwiftUI button configuration each tap.
enum MailExtensionSetup {
    /// Opens macOS System Settings directly to the per-app Extensions pane
    /// where the Mail toggle lives. Falls back to the top-level Privacy &
    /// Security pane when the deep-link is unavailable.
    static func openSystemSettingsExtensionsPane() {
        let candidates: [URL] = [
            URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?Extensions")!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions")!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        ]
        for url in candidates {
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
