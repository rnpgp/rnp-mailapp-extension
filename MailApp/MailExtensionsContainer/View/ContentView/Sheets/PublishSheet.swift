//
//  PublishSheet.swift
//  RNP
//
//  Progress / result sheet shown while a key is being published to
//  the keyserver. Extracted from ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct PublishSheet: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("publish.title")
                .font(.headline)
            HStack(spacing: 10) {
                if model.isPublishing {
                    ProgressView().controlSize(.small)
                }
                Text(model.publishMessage.localized)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("button.ok") { model.currentSheet = nil }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isPublishing)
                    .accessibilityIdentifier("contentview.publish.ok")
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
