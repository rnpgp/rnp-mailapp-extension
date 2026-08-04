//
//  ExtendExpirySheet.swift
//  RNP
//
//  Sheet for extending the expiration of a key. Extracted from
//  ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct ExtendExpirySheet: View {
    @ObservedObject var model: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("extendExpiry.title")
                .font(.headline)
            DatePicker(
                "extendExpiry.dateLabel",
                selection: $model.extendExpiryDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .accessibilityIdentifier("contentview.extendexpiry.datepicker")
            HStack(spacing: 12) {
                Spacer()
                Button("button.cancel") { model.currentSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("contentview.extendexpiry.cancel")
                Button("button.extend") {
                    model.extendSelectedExpiry()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("contentview.extendexpiry.extend")
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
