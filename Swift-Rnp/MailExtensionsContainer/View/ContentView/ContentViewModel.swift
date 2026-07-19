//
//  ContentViewModel.swift
//  Ribose container
//
//  UI state and actions for the key manager window.
//

import AppKit
import Foundation
import MailSecurityEngine

final class ContentViewModel: ObservableObject {
    @Published var selection: KeyInfo.ID?
    @Published var showGenerateSheet = false
    @Published var showDeleteConfirmation = false
    @Published var errorMessage: String?
    @Published private(set) var generateAlgorithm: KeyAlgorithm = .rsa

    let manager: KeysManager

    init(manager: KeysManager) {
        self.manager = manager
    }

    var keys: [KeyInfo] {
        manager.keys
    }

    var selectedKey: KeyInfo? {
        manager.keys.first { $0.id == selection }
    }

    // MARK: - Generate

    func beginGenerate(algorithm: KeyAlgorithm) {
        generateAlgorithm = algorithm
        showGenerateSheet = true
    }

    func generate(userID: String, algorithm: KeyAlgorithm) {
        manager.generate(userID: userID, algorithm: algorithm)
        propagateError()
    }

    // MARK: - Import

    /// Imports armored key data from the general pasteboard.
    func importFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              text.contains("BEGIN PGP")
        else {
            errorMessage = "The clipboard does not contain an armored OpenPGP key."
            return
        }
        manager.importKeys(Data(text.utf8))
        propagateError()
    }

    /// Imports keys from a user-selected key file.
    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data, .text]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an OpenPGP key file to import"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            manager.importKeys(data)
            propagateError()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export

    /// Copies the armored public key of the current selection to the
    /// general pasteboard.
    func exportSelectedToPasteboard() {
        guard let key = selectedKey else {
            return
        }
        guard let armored = manager.exportKey(fingerprint: key.fingerprint) else {
            errorMessage = "The key could not be exported."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: armored, as: UTF8.self), forType: .string)
    }

    // MARK: - Delete

    func deleteSelected() {
        guard let key = selectedKey else {
            return
        }
        manager.delete(key)
        selection = nil
        propagateError()
    }

    // MARK: - Error propagation

    private func propagateError() {
        errorMessage = manager.lastError
        manager.lastError = nil
    }
}
