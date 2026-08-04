//
//  FetchSheet.swift
//  RNP
//
//  Sheet for fetching a recipient key from keyservers / WKD.
//  Extracted from ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct FetchSheet: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("fetch.title").font(.headline)
            Text("fetch.message")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("fetch.query.placeholder", text: $model.fetchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .accessibilityIdentifier("contentview.fetch.query")

            Toggle(isOn: Binding(
                get: { model.autoFetchRecipientKeys },
                set: { model.autoFetchRecipientKeys = $0 }
            )) {
                Text("fetch.autoFetch")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("contentview.fetch.autofetch")

            if model.isDiscoveringKey {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("fetch.searching")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("contentview.fetch.progress")
            } else if let key = model.fetchedKey {
                Label(String(format: "fetch.found".localized, key.source), systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") {
                    model.currentSheet = nil
                    model.fetchQuery = ""
                    model.fetchedKey = nil
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("contentview.fetch.cancel")
                Button("button.search") {
                    model.discoverKey()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.fetchQuery.trimmingCharacters(in: .whitespaces).isEmpty || model.isDiscoveringKey)
                .accessibilityIdentifier("contentview.fetch.search")
                if model.fetchedKey != nil {
                    Button("button.import") {
                        model.importFetchedKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("contentview.fetch.import")
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
