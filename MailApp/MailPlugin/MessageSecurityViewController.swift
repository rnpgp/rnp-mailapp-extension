//
//  MessageSecurityViewController.swift
//  MailPlugin
//
//  OpenPGP security banner shown when the user clicks Mail's security
//  indicator: encryption status plus per-signer signature trust and key
//  actions.
//
//  Thin MailKit shell: the banner itself lives in the MailSecurityUI Swift
//  package (`MailSecurityBannerView`) so it can be tested without Mail.app;
//  this class only translates MailKit types into package types, and wires the
//  "Fetch signer key" action (fetch + import + re-decode) supplied by the
//  message security handler.
//

import AppKit
import MailKit
import MailSecurityEngine
import MailSecurityUI
import SwiftUI
import TrustStore

class MessageSecurityViewController: MEExtensionViewController {

    /// Refreshed banner content produced after a signer-key fetch and
    /// re-decode of the message.
    struct RefreshedBannerContent {
        let signers: [MailSecurityBannerView.Signer]
        let encryption: MailSecurityBannerView.EncryptionInfo?
        let decryptedAttachments: [DecryptedAttachment]
    }

    /// Fetch-and-redecode operation supplied by the handler: looks the
    /// signer's key up on the keyservers, imports it, and re-decodes the
    /// message to produce refreshed banner content.
    typealias SignerKeyFetch = (SignerContext) async -> Result<RefreshedBannerContent, KeyServerError>

    private let messageSigners: [MEMessageSigner]
    private let signerContexts: [SignerContext?]
    private let trustStore: TrustStore?
    private let encryption: MailSecurityBannerView.EncryptionInfo?
    private let decryptedAttachments: [DecryptedAttachment]
    private let fetchSignerKey: SignerKeyFetch?

    init(
        signers: [MEMessageSigner],
        contexts: [SignerContext?],
        trustStore: TrustStore?,
        encryption: MailSecurityBannerView.EncryptionInfo? = nil,
        decryptedAttachments: [DecryptedAttachment] = [],
        fetchSignerKey: SignerKeyFetch? = nil
    ) {
        self.messageSigners = signers
        self.signerContexts = contexts
        self.trustStore = trustStore
        self.encryption = encryption
        self.decryptedAttachments = decryptedAttachments
        self.fetchSignerKey = fetchSignerKey
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let signers = zip(messageSigners, signerContexts).map { signer, context in
            MailSecurityBannerView.Signer(label: signer.label, context: context)
        }
        view = makeRootView(signers: signers, encryption: encryption)
    }

    /// Composes the security banner with the decrypted-attachments
    /// panel below. The two are siblings under a single ScrollView so
    /// the user can scroll through long attachment lists without the
    /// banner scrolling out of view.
    private func makeRootView(
        signers: [MailSecurityBannerView.Signer],
        encryption: MailSecurityBannerView.EncryptionInfo?
    ) -> NSView {
        let banner = makeBanner(signers: signers, encryption: encryption)
        if decryptedAttachments.isEmpty {
            return banner
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(banner)

        let attachmentsHost = NSHostingController(
            rootView: DecryptedAttachmentsView(attachments: decryptedAttachments)
        )
        let attachmentsView = attachmentsHost.view
        attachmentsView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(attachmentsView)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }

    private func makeBanner(
        signers: [MailSecurityBannerView.Signer],
        encryption: MailSecurityBannerView.EncryptionInfo?
    ) -> MailSecurityBannerView {
        MailSecurityBannerView(
            signers: signers,
            trustStore: trustStore,
            encryption: encryption,
            onFetchSignerKey: makeFetchAction()
        )
    }

    /// Banner action driving the fetch operation. On success the banner is
    /// rebuilt from the refreshed decode; on failure the banner shows the
    /// error inline and re-enables the button.
    private func makeFetchAction() -> MailSecurityBannerView.SignerKeyFetchAction? {
        guard let fetchSignerKey else { return nil }
        return { [weak self] signer, completion in
            guard let self, let context = signer.context else {
                completion(.failure("Signer details are unavailable."))
                return
            }
            Task {
                let result = await fetchSignerKey(context)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    switch result {
                    case let .success(content):
                        self.view = self.makeBanner(
                            signers: content.signers,
                            encryption: content.encryption
                        )
                        completion(.success)
                    case let .failure(error):
                        completion(.failure(error.localizedDescription))
                    }
                }
            }
        }
    }
}
