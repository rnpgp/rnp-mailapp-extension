//
//  ImportKeyForm.swift
//  swift-rnp
//
//  Key import form used by the onboarding flow.
//

import SwiftUI

/// Collects an armored OpenPGP key block during onboarding.
public struct ImportKeyForm: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onImport: () -> Void
    let onBack: () -> Void

    public init(
        viewModel: OnboardingViewModel,
        onImport: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onImport = onImport
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("importForm.title")
                .font(.headline)

            Text("importForm.message")
                .font(.callout)

            TextEditor(text: $viewModel.importText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 180)
                .border(Color.secondary.opacity(0.25))
                .accessibilityIdentifier("importform.text")

            Button("importForm.fetchPlaceholder") {}
                .disabled(true)
                .font(.caption)
                .accessibilityIdentifier("importform.fetch")

            HStack {
                Button("button.back", action: onBack)
                    .accessibilityIdentifier("importform.back")
                Spacer()
                Button("button.import") {
                    onImport()
                }
                .disabled(!viewModel.canImport || viewModel.isWorking)
                .accessibilityIdentifier("importform.import")
            }
        }
        .frame(width: 420)
        .padding()
    }
}

#if DEBUG
struct ImportKeyForm_Previews: PreviewProvider {
    static var previews: some View {
        ImportKeyForm(viewModel: OnboardingViewModel(), onImport: {}, onBack: {})
    }
}
#endif
