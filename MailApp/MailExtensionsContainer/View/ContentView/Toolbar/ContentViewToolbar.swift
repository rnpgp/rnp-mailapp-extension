//
//  ContentViewToolbar.swift
//  RNP
//
//  Toolbar for the main key-manager window. Extracted from ContentView
//  in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

extension ContentView {
    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("generate.algorithm.ed25519") { model.beginGenerate(algorithm: .ed25519) }
                    .accessibilityIdentifier("contentview.generate-ed25519")
                Button("generate.algorithm.rsa") { model.beginGenerate(algorithm: .rsa) }
                    .accessibilityIdentifier("contentview.generate-rsa")
                Button("generate.algorithm.ecdsa") { model.beginGenerate(algorithm: .ecdsa) }
                    .accessibilityIdentifier("contentview.generate-ecdsa")
            } label: {
                Label("toolbar.generate.help", systemImage: "plus")
            }
            .menuIndicator(.hidden)
            .help("toolbar.generate.help")
            .accessibilityIdentifier("contentview.generate-menu")
            .accessibilityLabel("toolbar.generate.help")

            Menu {
                Button("import.fromKeyring") { model.currentSheet = .importFromKeyring }
                    .accessibilityIdentifier("contentview.import-keyring")
                Divider()
                Button("import.fromClipboard") { model.importFromPasteboard() }
                    .accessibilityIdentifier("contentview.import-clipboard")
                Button("import.fromFile") { model.importFromFile() }
                    .accessibilityIdentifier("contentview.import-file")
                if model.selectedTab == .recipients {
                    Button("import.fromKeyserver") {
                        model.currentSheet = .fetch
                    }
                    .accessibilityIdentifier("contentview.import-keyserver")
                }
            } label: {
                Label("toolbar.import.help", systemImage: "square.and.arrow.down")
            }
            .menuIndicator(.hidden)
            .help("toolbar.import.help")
            .accessibilityIdentifier("contentview.import-menu")
            .accessibilityLabel("toolbar.import.help")

            Button {
                model.exportSelectedPublicToPasteboard()
            } label: {
                Label("toolbar.export.help", systemImage: "square.and.arrow.up")
            }
            .disabled(model.selectedKey == nil)
            .help("toolbar.export.help")
            .accessibilityIdentifier("contentview.export-button")
            .accessibilityLabel("toolbar.export.help")

            Button {
                model.currentSheet = .detail
            } label: {
                Label("toolbar.details.help", systemImage: "info.circle")
            }
            .disabled(model.selectedKey == nil)
            .help("toolbar.details.help")
            .accessibilityIdentifier("contentview.details-button")
            .accessibilityLabel("toolbar.details.help")

            Button {
                model.showDeleteConfirmation = true
            } label: {
                Label("toolbar.delete.help", systemImage: "trash")
            }
            .disabled(model.selectedKey == nil)
            .help("toolbar.delete.help")
            .accessibilityIdentifier("contentview.delete-button")
            .accessibilityLabel("toolbar.delete.help")

            Button {
                model.refresh()
            } label: {
                Label("toolbar.refresh.help", systemImage: "arrow.clockwise")
            }
            .help("toolbar.refresh.help")
            .accessibilityIdentifier("contentview.refresh-button")
            .accessibilityLabel("toolbar.refresh.help")
        }
    }
}
