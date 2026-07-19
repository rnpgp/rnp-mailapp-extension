//
//  MessageSecurityViewController.swift
//  MailPlugin
//
//  Signature-status banner shown when the user clicks Mail's security
//  indicator for a signed message, now augmented with per-signer trust.
//

import AppKit
import MailKit
import MailSecurityEngine
import Rnp
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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let title = NSTextField(labelWithString: "OpenPGP signature")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let stack = NSStackView(views: [title] + signerRows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        ])
    }

    private var signerRows: [NSView] {
        guard !messageSigners.isEmpty else {
            return [NSTextField(wrappingLabelWithString: "No valid signatures found on this message.")]
        }
        return zip(messageSigners, signerContexts).map { signer, context in
            row(for: signer, context: context)
        }
    }

    private func row(
        for signer: MEMessageSigner,
        context: SignerContext?
    ) -> NSView {
        let status = context.flatMap { RnpSignatureStatus(rawValue: $0.status) } ?? .unknown
        let model: SignerTrustViewModel
        if let trustStore = trustStore {
            let trust: TrustState
            if let fingerprint = context?.fingerprint {
                trust = trustStore.state(forFpr: fingerprint)
            } else {
                trust = .unverified
            }
            model = mapSignerTrust(status: status, trust: trust)
        } else {
            model = SignerTrustViewModel(
                label: "Trust state unavailable",
                detail: "Trust information cannot be loaded while the keyring is unavailable.",
                intent: .caution,
                reviewDeepLink: false
            )
        }

        let nameLabel = NSTextField(labelWithString: signer.label)
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let trustLabel = NSTextField(labelWithString: model.label)
        trustLabel.textColor = color(for: model.intent)
        trustLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        let detailLabel = NSTextField(wrappingLabelWithString: model.detail)
        detailLabel.textColor = NSColor.secondaryLabelColor
        detailLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        var rows: [NSView] = [
            nameLabel,
            trustLabel,
            detailLabel,
        ]

        if model.reviewDeepLink, let fingerprint = context?.fingerprint {
            let link = NSButton(title: "Review in RnpMail", target: self, action: #selector(openReviewLink(_:)))
            link.identifier = NSUserInterfaceItemIdentifier(fingerprint)
            link.bezelStyle = .inline
            rows.append(link)
        }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    private func color(for intent: SignerTrustIntent) -> NSColor {
        switch intent {
        case .positive:
            return .systemGreen
        case .neutral:
            return .secondaryLabelColor
        case .caution:
            return .systemOrange
        case .critical:
            return .systemRed
        }
    }

    @objc private func openReviewLink(_ sender: NSButton) {
        guard let fingerprint = sender.identifier?.rawValue,
              let url = URL(string: "rnpmail://review/\(fingerprint)")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
