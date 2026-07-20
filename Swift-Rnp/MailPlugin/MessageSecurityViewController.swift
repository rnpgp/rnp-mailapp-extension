//
//  MessageSecurityViewController.swift
//  MailPlugin
//
//  Signature-status banner shown when the user clicks Mail's security
//  indicator for a signed message, now augmented with per-signer trust.
//
//  Thin MailKit shell: the banner itself lives in the MailSecurityUI Swift
//  package (`MailSecurityBannerView`) so it can be tested without Mail.app;
//  this class only translates MailKit types into package types.
//

import AppKit
import MailKit
import MailSecurityEngine
import MailSecurityUI
import TrustStore

class MessageSecurityViewController: MEExtensionViewController {

    private let messageSigners: [MEMessageSigner]
    private let signerContexts: [SignerContext?]
    private let trustStore: TrustStore?

    init(
        signers: [MEMessageSigner],
        contexts: [SignerContext?],
        trustStore: TrustStore?
    ) {
        self.messageSigners = signers
        self.signerContexts = contexts
        self.trustStore = trustStore
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
        view = MailSecurityBannerView(signers: signers, trustStore: trustStore)
    }
}
