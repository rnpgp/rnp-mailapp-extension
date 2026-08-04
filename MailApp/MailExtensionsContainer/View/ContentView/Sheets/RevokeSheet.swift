//
//  RevokeSheet.swift
//  RNP
//
//  Sheet for revoking a key. Extracted from ContentView in
//  TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct RevokeSheet: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
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
                Button("button.cancel") { model.currentSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("contentview.revoke.cancel")
                Button("button.revoke", role: .destructive) {
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
}
