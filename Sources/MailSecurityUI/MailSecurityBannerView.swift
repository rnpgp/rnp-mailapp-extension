//
//  MailSecurityBannerView.swift
//  swift-rnp
//
//  AppKit signature-status banner shown when the user clicks Mail's security
//  indicator for a signed message, augmented with per-signer trust.
//
//  Moved out of the MailPlugin appex into this SwiftPM target so the banner
//  can be unit- and snapshot-tested without Mail.app. Kept free of MailKit
//  types: the caller translates `MEMessageSigner` into `Signer` values.
//

import AppKit
import MailSecurityEngine
import Rnp
import TrustStore

/// Renders the "OpenPGP signature" banner: a title plus one row stack per
/// signer with the signer's trust state and, when useful, a deep link to
/// review the key in the container app (`rnpmail://review/<fpr>`).
public final class MailSecurityBannerView: NSView {

    /// One signer row in the banner.
    public struct Signer {
        /// Display name, typically the signer's user ID or fingerprint.
        public let label: String
        /// Decode-time context for trust lookup; `nil` when unavailable.
        public let context: SignerContext?

        public init(label: String, context: SignerContext?) {
            self.label = label
            self.context = context
        }
    }

    private let signers: [Signer]
    private let trustStore: TrustStore?

    public init(signers: [Signer], trustStore: TrustStore?) {
        self.signers = signers
        self.trustStore = trustStore
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        setUpViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpViews() {
        let title = NSTextField(labelWithString: "OpenPGP signature")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let stack = NSStackView(views: [title] + signerRows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(10, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        // The bottom constraint is not required so that a host forcing an
        // explicit height wins over content sizing, but it is strong enough
        // to give the view a well-defined fitting height for tests.
        let bottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        bottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            bottom,
        ])
    }

    private var signerRows: [NSView] {
        guard !signers.isEmpty else {
            return [NSTextField(wrappingLabelWithString: "No valid signatures found on this message.")]
        }
        return signers.map { row(for: $0) }
    }

    private func row(for signer: Signer) -> NSView {
        let status = signer.context.flatMap { RnpSignatureStatus(rawValue: $0.status) } ?? .unknown
        let model: SignerTrustViewModel
        if let trustStore = trustStore {
            let trust: TrustState
            if let fingerprint = signer.context?.fingerprint {
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

        let intentColor = color(for: model.intent)

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbolName(for: model.intent),
            accessibilityDescription: nil
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: intentColor)
            .applying(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let nameLabel = NSTextField(labelWithString: signer.label)
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let trustLabel = NSTextField(labelWithString: model.label)
        trustLabel.textColor = intentColor
        trustLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        let detailLabel = NSTextField(wrappingLabelWithString: model.detail)
        detailLabel.textColor = NSColor.secondaryLabelColor
        detailLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        var rows: [NSView] = [
            nameLabel,
            trustLabel,
            detailLabel,
        ]

        if model.reviewDeepLink, let fingerprint = signer.context?.fingerprint {
            let link = NSButton(title: "Review in RnpMail", target: self, action: #selector(openReviewLink(_:)))
            link.identifier = NSUserInterfaceItemIdentifier(fingerprint)
            link.bezelStyle = .inline
            rows.append(link)
        }

        let textStack = NSStackView(views: rows)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let rowStack = NSStackView(views: [icon, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 8
        return rowStack
    }

    private func symbolName(for intent: SignerTrustIntent) -> String {
        switch intent {
        case .positive:
            return "checkmark.shield.fill"
        case .neutral:
            return "questionmark.shield"
        case .caution:
            return "exclamationmark.shield.fill"
        case .critical:
            return "xmark.shield.fill"
        }
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
