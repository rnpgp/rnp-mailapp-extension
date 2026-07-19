//
//  OnboardingView.swift
//  swift-rnp
//
//  First-launch onboarding flow: welcome, create/import, done.
//

import SwiftUI
import MailSecurityEngine

/// First-launch onboarding sheet.
///
/// The view is driven by `OnboardingViewModel`; all side effects are provided
/// as closures so the view remains testable without a live keyring.
public struct OnboardingView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: OnboardingViewModel

    private let onGenerate: (String, KeyAlgorithm, String, UInt32, Bool) -> Result<OnboardingGenerationResult, Error>
    private let onImport: (Data) -> Result<[KeyInfo], Error>
    private let onComplete: () -> Void

    public init(
        isPresented: Binding<Bool>,
        viewModel: OnboardingViewModel = OnboardingViewModel(),
        onGenerate: @escaping (String, KeyAlgorithm, String, UInt32, Bool) -> Result<OnboardingGenerationResult, Error>,
        onImport: @escaping (Data) -> Result<[KeyInfo], Error>,
        onComplete: @escaping () -> Void = {}
    ) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onGenerate = onGenerate
        self.onImport = onImport
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack {
            switch viewModel.currentStep {
            case .welcome:
                welcomePage
            case .createOrImport:
                createOrImportPage
            case .generateForm:
                GenerateKeyForm(
                    viewModel: viewModel,
                    onGenerate: { viewModel.generate(using: onGenerate) },
                    onBack: { viewModel.goBack() }
                )
            case .importForm:
                ImportKeyForm(
                    viewModel: viewModel,
                    onImport: { viewModel.importKeys(using: onImport) },
                    onBack: { viewModel.goBack() }
                )
            case .done(let url):
                donePage(revocationURL: url)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .alert(
            "Could not continue",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Text("Welcome to Swift-Rnp")
                .font(.title)
            Text("A simple OpenPGP key manager for Apple Mail.")
                .font(.body)
                .multilineTextAlignment(.center)
            Button("Get started") {
                viewModel.continueFromWelcome()
            }
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: 360)
    }

    private var createOrImportPage: some View {
        VStack(spacing: 20) {
            Text("Set up your keyring")
                .font(.title2)
            Text("Create a new key pair or import an existing one.")
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Create new key") {
                    viewModel.chooseCreate()
                }
                .controlSize(.large)
                Button("Import existing key") {
                    viewModel.chooseImport()
                }
                .controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: 360)
    }

    private func donePage(revocationURL: URL?) -> some View {
        VStack(spacing: 16) {
            Text("You're all set")
                .font(.title2)

            if let url = revocationURL {
                Text("A revocation certificate was saved to:")
                Text(url.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Keep it somewhere safe. You will need it if you ever lose access to your key.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Publish public key (task 06)") {}
                .disabled(true)

            Button("Done") {
                onComplete()
                isPresented = false
            }
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: 420)
    }
}

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(
            isPresented: .constant(true),
            onGenerate: { _, _, _, _, _ in
                .success(OnboardingGenerationResult(
                    userID: "Preview <preview@example.com>",
                    fingerprint: "ABCD1234",
                    revocationCertificateURL: URL(fileURLWithPath: "/tmp/rev.asc")
                ))
            },
            onImport: { _ in .success([]) }
        )
    }
}
#endif
