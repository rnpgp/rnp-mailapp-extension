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
            Text("Import an existing key")
                .font(.headline)

            Text("Paste an armored public or private key block:")
                .font(.callout)

            TextEditor(text: $viewModel.importText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 180)
                .border(Color.secondary.opacity(0.25))

            Button("Fetch by email (coming in task 06)") {}
                .disabled(true)
                .font(.caption)

            HStack {
                Button("Back", action: onBack)
                Spacer()
                Button("Import") {
                    onImport()
                }
                .disabled(!viewModel.canImport || viewModel.isWorking)
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
