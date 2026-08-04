//
//  ClipboardImportSheet.swift
//  RNP
//
//  Sheet confirming import of a PGP block detected on the pasteboard.
//  Extracted from ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct ClipboardImportSheet: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("clipboardImport.title")
                .font(.headline)
            Text("clipboardImport.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") {
                    model.currentSheet = nil
                    model.clipboardText = ""
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("contentview.clipboard.cancel")
                Button("button.import") {
                    model.confirmClipboardImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("contentview.clipboard.import")
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
