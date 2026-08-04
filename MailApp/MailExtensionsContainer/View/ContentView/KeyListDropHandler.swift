//
//  KeyListDropHandler.swift
//  RNP
//
//  Drag-drop handler for the key list: accepts file URLs (key files),
//  raw PGP blocks (text drag), and raw data. Extracted from
//  ContentView in TODO.complete/22.
//

import AppKit
import RnpMailUI
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    /// Returns true if any provider was handled. Each provider is
    /// loaded asynchronously; on success, the resulting key bytes
    /// are forwarded to `model.importData(_:)` on the main queue.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    DispatchQueue.global(qos: .userInitiated).async {
                        guard let keyData = try? Data(contentsOf: url) else { return }
                        DispatchQueue.main.async {
                            model.importData(keyData)
                        }
                    }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string = string, string.contains("BEGIN PGP") else { return }
                    DispatchQueue.main.async {
                        model.importData(Data(string.utf8))
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, _ in
                    guard let data = item as? Data else { return }
                    DispatchQueue.main.async {
                        model.importData(data)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
