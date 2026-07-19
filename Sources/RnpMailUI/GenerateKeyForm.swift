//
//  GenerateKeyForm.swift
//  swift-rnp
//
//  Key generation form used by the onboarding flow.
//

import SwiftUI
import MailSecurityEngine

/// Collects the details for a new OpenPGP key during onboarding.
public struct GenerateKeyForm: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onGenerate: () -> Void
    let onBack: () -> Void

    public init(
        viewModel: OnboardingViewModel,
        onGenerate: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onGenerate = onGenerate
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create your key")
                .font(.headline)

            HStack(spacing: 12) {
                TextField("Full name", text: $viewModel.name)
                TextField("Email", text: $viewModel.email)
            }

            Picker("Algorithm", selection: $viewModel.algorithm) {
                Text("Ed25519 (recommended)").tag(KeyAlgorithm.ed25519)
                Text("RSA-3072 (maximum compatibility)").tag(KeyAlgorithm.rsa)
                Text("ECDSA P-256").tag(KeyAlgorithm.ecdsa)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Expires in")
                Picker("Expires in", selection: $viewModel.expirationDays) {
                    Text("1 year").tag(365)
                    Text("2 years").tag(730)
                    Text("No expiry").tag(0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                SecureField("Passphrase", text: $viewModel.passphrase)
                PassphraseStrengthMeter(passphrase: viewModel.passphrase)
            }

            SecureField("Confirm passphrase", text: $viewModel.confirmPassphrase)

            if viewModel.passphrase != viewModel.confirmPassphrase, !viewModel.confirmPassphrase.isEmpty {
                Text("The passphrases do not match.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("Save to Keychain with Touch ID", isOn: $viewModel.useTouchID)

            HStack {
                Button("Back", action: onBack)
                Spacer()
                Button("Create key") {
                    onGenerate()
                }
                .disabled(!viewModel.canGenerate || viewModel.isWorking)
            }
        }
        .frame(width: 420)
        .padding()
    }
}

#if DEBUG
struct GenerateKeyForm_Previews: PreviewProvider {
    static var previews: some View {
        GenerateKeyForm(viewModel: OnboardingViewModel(), onGenerate: {}, onBack: {})
    }
}
#endif
