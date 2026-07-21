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
        VStack(spacing: 24) {
            progressIndicator
                .padding(.top, 4)
            stepContent
                .transition(.opacity)
                .id(stepIdentifier)
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 400)
        .animation(.default, value: viewModel.currentStep)
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

    @ViewBuilder
    private var stepContent: some View {
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

    // MARK: - Progress

    /// Coarse phase for the progress dots: welcome, setup, done.
    private var stepIndex: Int {
        switch viewModel.currentStep {
        case .welcome:
            return 0
        case .createOrImport, .generateForm, .importForm:
            return 1
        case .done:
            return 2
        }
    }

    /// Distinct identity per step so the crossfade transition also fires
    /// between steps that share a progress phase.
    private var stepIdentifier: String {
        switch viewModel.currentStep {
        case .welcome:
            return "welcome"
        case .createOrImport:
            return "createOrImport"
        case .generateForm:
            return "generateForm"
        case .importForm:
            return "importForm"
        case .done:
            return "done"
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(index <= stepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "onboarding.progress".localized, stepIndex + 1, 3))
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("onboarding.welcome.title")
                .font(.largeTitle.weight(.semibold))
            Text("onboarding.welcome.subtitle")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("onboarding.welcome.button") {
                viewModel.continueFromWelcome()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.welcome.continue")
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var createOrImportPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("onboarding.setup.title")
                .font(.title2.weight(.semibold))
            Text("onboarding.setup.subtitle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack(spacing: 16) {
                OnboardingOptionCard(
                    title: "onboarding.createKey",
                    icon: "key.fill",
                    identifier: "onboarding.create",
                    action: { viewModel.chooseCreate() }
                )
                OnboardingOptionCard(
                    title: "onboarding.importKey",
                    icon: "square.and.arrow.down",
                    identifier: "onboarding.import",
                    action: { viewModel.chooseImport() }
                )
            }
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func donePage(revocationURL: URL?) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("onboarding.done.title")
                .font(.title2.weight(.semibold))

            if let url = revocationURL {
                VStack(spacing: 8) {
                    Text("onboarding.done.revocationLabel")
                        .font(.callout.weight(.medium))
                    Text(url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("onboarding.done.revocation-path")
                    Text("onboarding.done.revocationHint")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: 420)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button("onboarding.done.publishPlaceholder") {}
                .disabled(true)
                .accessibilityIdentifier("onboarding.done.publish")

            Button("button.done") {
                onComplete()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.done.finish")
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Card-style button used for the create/import choice.
private struct OnboardingOptionCard: View {
    let title: LocalizedStringKey
    let icon: String
    let identifier: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 170, height: 120)
            .background(
                .quaternary.opacity(isHovering ? 1 : 0.6),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier(identifier)
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
