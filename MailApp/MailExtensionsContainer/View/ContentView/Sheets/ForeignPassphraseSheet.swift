//
//  ForeignPassphraseSheet.swift
//  RNP
//
//  Sheet + form asking for the passphrase of an imported secret key
//  that is protected by a foreign passphrase (different from the
//  keyring passphrase). Extracted from ContentView in TODO.complete/22.
//

import MailSecurityEngine
import RnpMailUI
import SwiftUI

struct ForeignPassphraseSheet: View {
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

struct ForeignPassphraseForm: View {
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
