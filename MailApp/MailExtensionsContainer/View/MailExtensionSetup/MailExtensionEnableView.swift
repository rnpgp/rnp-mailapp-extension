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

    var body: some View {
        VStack(alignment: .leading, spacing: RnpSpacing.lg) {
            header

            stepsList

            deepLinkButton
                .padding(.top, RnpSpacing.xs)

            Divider()
                .padding(.vertical, RnpSpacing.xxs)

            footerButtons
        }
        .padding(RnpSpacing.xl)
        .frame(width: 520)
        .accessibilityIdentifier("mailextension.view")
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
                dismiss()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("mailextension.enabled")
        }
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
