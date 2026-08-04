//
//  KeyringUnlockSheet.swift
//  RNP
//
//  Sheet unlocking a Touch ID-protected keyring: primary Touch ID
//  button, with manual keyring-passphrase entry as the fallback when
//  Touch ID fails or was cancelled. Dismisses itself once the keyring
//  is unlocked. Extracted from ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct KeyringUnlockSheet: View {
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
        .onChange(of: model.keyringLocked, initial: false) { _, locked in
            if !locked {
                dismiss()
            }
        }
    }
}
