//
//  RotateSheet.swift
//  RNP
//
//  Sheet confirming subkey rotation. Extracted from ContentView in
//  TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct RotateSheet: View {
    @ObservedObject var model: ContentViewModel
    let kind: RotateKind

    var body: some View {
        let messageKey: String = kind == .encryption ? "rotate.encryption.message" : "rotate.signing.message"
        return VStack(spacing: 16) {
            Text("rotate.title")
                .font(.headline)
            Text(messageKey.localized)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") { model.currentSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("contentview.rotate.cancel")
                Button("button.rotate") {
                    switch kind {
                    case .encryption: model.rotateEncryptionSubkey()
                    case .signing:    model.rotateSigningSubkey()
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
}
