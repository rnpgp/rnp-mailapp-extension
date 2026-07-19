//
//  MessageSecurityViewController.swift
//  MailPlugin
//
//  Minimal signature-status banner shown when the user clicks Mail's
//  security indicator for a signed message.
//

import AppKit
import MailKit

class MessageSecurityViewController: MEExtensionViewController {

    private let messageSigners: [MEMessageSigner]

    init(signers: [MEMessageSigner]) {
        messageSigners = signers
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let title = NSTextField(labelWithString: "OpenPGP signature")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let details = NSTextField(wrappingLabelWithString: signerDescription)
        details.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, details])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        ])
    }

    private var signerDescription: String {
        guard !messageSigners.isEmpty else {
            return "No valid signatures found on this message."
        }
        let names = messageSigners
            .map(\.label)
            .joined(separator: ", ")
        return "Signed by: \(names)"
    }
}
