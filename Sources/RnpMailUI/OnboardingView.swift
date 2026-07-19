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
            "error.onboarding.title",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("button.ok") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Text("onboarding.welcome.title")
                .font(.title)
            Text("onboarding.welcome.subtitle")
                .font(.body)
                .multilineTextAlignment(.center)
            Button("onboarding.welcome.button") {
                viewModel.continueFromWelcome()
            }
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.welcome.continue")
        }
        .padding()
        .frame(maxWidth: 360)
    }

    private var createOrImportPage: some View {
        VStack(spacing: 20) {
            Text("onboarding.setup.title")
                .font(.title2)
            Text("onboarding.setup.subtitle")
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("onboarding.createKey") {
                    viewModel.chooseCreate()
                }
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.create")
                Button("onboarding.importKey") {
                    viewModel.chooseImport()
                }
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.import")
            }
        }
        .padding()
        .frame(maxWidth: 360)
    }

    private func donePage(revocationURL: URL?) -> some View {
        VStack(spacing: 16) {
            Text("onboarding.done.title")
                .font(.title2)

            if let url = revocationURL {
                Text("onboarding.done.revocationLabel")
                Text(url.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("onboarding.done.revocation-path")
                Text("onboarding.done.revocationHint")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("onboarding.done.publishPlaceholder") {}
                .disabled(true)
                .accessibilityIdentifier("onboarding.done.publish")

            Button("button.done") {
                onComplete()
                isPresented = false
            }
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.done.finish")
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
