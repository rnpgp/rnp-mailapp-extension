//
//  GenerateKeySheet.swift
//  RNP
//
//  Sheet collecting the user ID for a new key. Extracted from
//  ContentView in TODO.complete/22.
//

import MailSecurityEngine
import RnpMailUI
import SwiftUI

struct GenerateKeySheet: View {
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
