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
    private let encryption: MailSecurityBannerView.EncryptionInfo?

    init(
        signers: [MEMessageSigner],
        contexts: [SignerContext?],
        trustStore: TrustStore?,
        encryption: MailSecurityBannerView.EncryptionInfo? = nil
    ) {
        self.messageSigners = signers
        self.signerContexts = contexts
        self.trustStore = trustStore
        self.encryption = encryption
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
        view = MailSecurityBannerView(signers: signers, trustStore: trustStore, encryption: encryption)
    }
}
