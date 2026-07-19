//
//  ContentView.swift
//  Ribose container
//
//  Key manager window: toolbar with generate/import/export/delete actions
//  above the key list.
//

import MailSecurityEngine
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("OpenPGP Keys")
                .font(.title2)

            HStack(spacing: 24) {
                Menu {
                    Button("RSA-3072") { model.beginGenerate(algorithm: .rsa) }
                    Button("ECDSA P-256") { model.beginGenerate(algorithm: .ecdsa) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Generate a new key")

                Menu {
                    Button("From Clipboard") { model.importFromPasteboard() }
                    Button("From File…") { model.importFromFile() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .help("Import an armored key")

                Button {
                    model.exportSelectedToPasteboard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedKey == nil)
                .help("Copy the armored public key to the clipboard")

                Button {
                    model.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedKey == nil)
                .help("Delete the selected key")
            }
            .font(.system(size: 32))

            KeysListView(keys: model.keys, selection: $model.selection)
        }
        .padding()
        .frame(minWidth: 560, minHeight: 360)
        .sheet(isPresented: $model.showGenerateSheet) {
            GenerateKeySheet(algorithm: model.generateAlgorithm) { userID, algorithm in
                model.generate(userID: userID, algorithm: algorithm)
            }
        }
        .alert("Delete key?", isPresented: $model.showDeleteConfirmation) {
            Button("Delete", role: .destructive) { model.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the key pair from the shared keyring. This cannot be undone.")
        }
        .alert(
            "Key operation failed",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Sheet collecting the user ID for a new key.
private struct GenerateKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userID = ""

    let algorithm: KeyAlgorithm
    let onGenerate: (String, KeyAlgorithm) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate key (\(algorithm.rawValue))")
                .font(.headline)
            Text("User ID, e.g. “Alice <alice@example.com>”:")
                .font(.callout)
            TextField("Name <email>", text: $userID)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Generate") {
                    onGenerate(userID, algorithm)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(userID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: ContentViewModel(manager: KeysManager()))
    }
}
#endif
