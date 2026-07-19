//
//  MessageDecoder.swift
//  swift-rnp
//
//  Decoding side of the mail security engine: detects OpenPGP content in an
//  incoming RFC 822 message (PGP/MIME or inline), decrypts and verifies it,
//  and unwraps it back into a plain message for Mail to display.
//

import Foundation
import Rnp

extension MailSecurityEngine {
    /// Accumulated security outcome of a decode pass.
    struct DecodeOutcome {
        var processedAny = false
        var isEncrypted = false
        var signers: [RnpSignatureInfo] = []
        var signingError: Error?
        var encryptionError: Error?
    }

    /// Entry point running under the key manager lock; see `decode(_:)`.
    func decodeUnlocked(_ message: Data, rnp: Rnp) throws -> DecodedMessage? {
        let parsed = MimeMessage.parse(message)
        let contentType = parsed.contentType
        let mediaType = (contentType?.type ?? "", contentType?.subtype ?? "")
        let pgpProtocol = contentType?.parameters["protocol"] ?? ""

        switch (mediaType, pgpProtocol) {
        case (("multipart", "signed"), "application/pgp-signature"):
            return try decodePGPMimeSigned(parsed, rnp: rnp)
        case (("multipart", "encrypted"), "application/pgp-encrypted"):
            return try decodePGPMimeEncrypted(parsed, rnp: rnp)
        case (("multipart", _), _):
            return try decodeInlineMultipart(parsed, rnp: rnp)
        default:
            return try decodeInlineSingle(parsed, rnp: rnp)
        }
    }

    // MARK: - PGP/MIME

    /// Decodes a multipart/signed message (RFC 3156 section 5): verifies the
    /// detached signature in the second part against the exact bytes of the
    /// first part, then unwraps the message for display.
    private func decodePGPMimeSigned(_ parsed: MimeMessage, rnp: Rnp) throws -> DecodedMessage? {
        guard let rawParts = parsed.rawPartEntities, rawParts.count >= 2,
              let parts = parsed.parts, parts.count >= 2
        else {
            throw MailSecurityError.malformedMessage(
                "multipart/signed with fewer than two parts"
            )
        }
        let signedData = MimeMessage.crlfNormalized(rawParts[0])
        let signature = parts[1].decodedBody()
        let verification = try rnp.verifyDetachedDetailed(signature: signature, data: signedData)

        let signers = signerInfos(verification.signatures, rnp: rnp)
        let error = signingError(for: signers)

        // Unwrap: drop the multipart wrapping, promote the signed entity's
        // Content-* headers to the top level.
        let inner = parts[0]
        var headers = nonContentHeaders(of: parsed)
        headers.append(contentsOf: inner.headers)
        let data = serialize(headers: headers, body: inner.body, eol: parsed.eol)
        return DecodedMessage(
            data: data,
            security: SecurityInformation(
                isEncrypted: false,
                signers: signers,
                signingError: error,
                encryptionError: nil
            )
        )
    }

    /// Decodes a multipart/encrypted message (RFC 3156 section 4): decrypts
    /// the second part (also verifying nested signatures), then unwraps the
    /// recovered MIME entity for display.
    private func decodePGPMimeEncrypted(_ parsed: MimeMessage, rnp: Rnp) throws -> DecodedMessage? {
        guard let parts = parsed.parts, parts.count >= 2 else {
            throw MailSecurityError.malformedMessage(
                "multipart/encrypted with fewer than two parts"
            )
        }
        let ciphertext = parts[1].decodedBody()
        let (decrypted, outcome) = processOpenPGPBlob(ciphertext, rnp: rnp)
        guard outcome.processedAny else {
            // Decryption failed (wrong passphrase, missing key, tampered
            // integrity protection): let Mail show the original message with
            // the error reported in the security banner.
            return DecodedMessage(
                data: nil,
                security: SecurityInformation(
                    isEncrypted: true,
                    signers: [],
                    signingError: nil,
                    encryptionError: outcome.encryptionError
                        ?? MailSecurityError.malformedMessage("undecryptable content")
                )
            )
        }

        let signers = signerInfos(outcome.signers, rnp: rnp)
        // The decrypted entity carries its own Content-* headers; splicing
        // it after the envelope headers restores the original message.
        let data = serialize(
            headers: nonContentHeaders(of: parsed),
            body: decrypted ?? Data(),
            eol: parsed.eol
        )
        return DecodedMessage(
            data: data,
            security: SecurityInformation(
                isEncrypted: true,
                signers: signers,
                signingError: signingError(for: signers),
                encryptionError: nil
            )
        )
    }

    // MARK: - Inline PGP

    /// Decodes a single-part message whose body carries inline OpenPGP
    /// armor. Returns `nil` when the body has no armor blocks.
    private func decodeInlineSingle(_ parsed: MimeMessage, rnp: Rnp) throws -> DecodedMessage? {
        let body = parsed.decodedBody()
        var outcome = DecodeOutcome()
        guard let newBody = processArmorBlocks(in: body, outcome: &outcome, rnp: rnp) else {
            return nil
        }
        var headers = parsed.headers
        replaceTransferEncoding(in: &headers, with: "8bit")
        return DecodedMessage(
            data: serialize(headers: headers, body: newBody, eol: parsed.eol),
            security: securityInformation(for: outcome, rnp: rnp)
        )
    }

    /// Decodes a multipart message that is not itself PGP/MIME by scanning
    /// leaf parts for inline armor. Returns `nil` when nothing is found.
    private func decodeInlineMultipart(_ parsed: MimeMessage, rnp: Rnp) throws -> DecodedMessage? {
        var outcome = DecodeOutcome()
        guard let newBody = processEntityBody(parsed, outcome: &outcome, rnp: rnp) else {
            return nil
        }
        return DecodedMessage(
            data: serialize(headers: parsed.headers, body: newBody, eol: parsed.eol),
            security: securityInformation(for: outcome, rnp: rnp)
        )
    }

    /// Recursively processes a multipart body, replacing leaf parts that
    /// carried armor. Returns the rebuilt body, or `nil` when no leaf
    /// changed.
    private func processEntityBody(
        _ entity: MimeMessage,
        outcome: inout DecodeOutcome,
        rnp: Rnp
    ) -> Data? {
        guard let parts = entity.parts, let rawParts = entity.rawPartEntities,
              let boundary = entity.contentType?.boundary
        else {
            return nil
        }
        var changed = false
        var newParts: [Data] = []
        for (part, rawPart) in zip(parts, rawParts) {
            if part.parts != nil {
                // Nested multipart: rebuild it and re-wrap with its headers.
                if let rebuilt = processEntityBody(part, outcome: &outcome, rnp: rnp) {
                    newParts.append(serialize(headers: part.headers, body: rebuilt, eol: part.eol))
                    changed = true
                } else {
                    newParts.append(rawPart)
                }
            } else {
                let body = part.decodedBody()
                if let newBody = processArmorBlocks(in: body, outcome: &outcome, rnp: rnp) {
                    var headers = part.headers
                    replaceTransferEncoding(in: &headers, with: "8bit")
                    newParts.append(serialize(headers: headers, body: newBody, eol: part.eol))
                    changed = true
                } else {
                    newParts.append(rawPart)
                }
            }
        }
        guard changed else {
            return nil
        }
        var body = Data()
        for part in newParts {
            appendLine("--\(boundary)", to: &body, eol: entity.eol)
            body.append(part)
            appendPartEndOfLine(&body, eol: entity.eol)
        }
        appendLine("--\(boundary)--", to: &body, eol: entity.eol)
        return body
    }

    // MARK: - Armor block processing

    /// Finds and processes OpenPGP armor blocks in `body`. Returns the body
    /// with processed blocks replaced by their payload, or `nil` when no
    /// block produced a security outcome.
    private func processArmorBlocks(
        in body: Data,
        outcome: inout DecodeOutcome,
        rnp: Rnp
    ) -> Data? {
        let blocks = armorBlocks(in: body)
        guard !blocks.isEmpty else {
            return nil
        }
        var result = body
        var foundAny = false
        // Replace from the end so earlier ranges stay valid.
        for block in blocks.reversed() {
            let (payload, blockOutcome) = processOpenPGPBlob(block.data, rnp: rnp)
            guard blockOutcome.processedAny else {
                continue
            }
            foundAny = true
            outcome.processedAny = true
            outcome.isEncrypted = outcome.isEncrypted || blockOutcome.isEncrypted
            outcome.signers.append(contentsOf: blockOutcome.signers)
            outcome.signingError = outcome.signingError ?? blockOutcome.signingError
            outcome.encryptionError = outcome.encryptionError ?? blockOutcome.encryptionError
            if let payload {
                result.replaceSubrange(block.range, with: payload)
            }
        }
        return foundAny ? result : nil
    }

    /// A located ASCII armor block.
    private struct ArmorBlock {
        let range: Range<Int>
        let data: Data
    }

    /// Locates "BEGIN PGP MESSAGE"/"BEGIN PGP SIGNED MESSAGE" armor blocks.
    private func armorBlocks(in body: Data) -> [ArmorBlock] {
        var blocks: [ArmorBlock] = []
        let markers: [(begin: Data, end: Data)] = [
            (Data("-----BEGIN PGP MESSAGE-----".utf8), Data("-----END PGP MESSAGE-----".utf8)),
            (
                Data("-----BEGIN PGP SIGNED MESSAGE-----".utf8),
                Data("-----END PGP SIGNATURE-----".utf8)
            ),
        ]
        for marker in markers {
            var searchStart = body.startIndex
            while let begin = body.range(of: marker.begin, in: searchStart ..< body.endIndex),
                  let end = body.range(of: marker.end, in: begin.upperBound ..< body.endIndex)
            {
                // Include the END line's trailing newline when present.
                var blockEnd = end.upperBound
                if body[blockEnd...].starts(with: Data("\r\n".utf8)) {
                    blockEnd += 2
                } else if blockEnd < body.endIndex, body[blockEnd] == 0x0A {
                    blockEnd += 1
                }
                blocks.append(ArmorBlock(
                    range: begin.lowerBound ..< blockEnd,
                    data: Data(body[begin.lowerBound ..< blockEnd])
                ))
                searchStart = blockEnd
            }
        }
        return blocks.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - OpenPGP blob processing

    /// Processes one OpenPGP blob (armored or binary): decrypts it when
    /// encrypted and verifies any embedded or cleartext signatures.
    ///
    /// `verifyDetailed` drives both decryption and signature verification in
    /// librnp, so sign+encrypt is handled in one pass; when librnp reports
    /// no signatures but the payload is itself OpenPGP data (implementations
    /// that do not verify nested signatures), one nested pass is attempted.
    private func processOpenPGPBlob(
        _ blob: Data,
        rnp: Rnp
    ) -> (payload: Data?, outcome: DecodeOutcome) {
        var outcome = DecodeOutcome()
        let verification: RnpVerification
        do {
            verification = try rnp.verifyDetailed(blob)
        } catch {
            // Not processable: undecryptable (wrong passphrase, missing key,
            // broken integrity) or not OpenPGP data at all.
            outcome.encryptionError = error
            return (nil, outcome)
        }

        var payload = verification.payload
        outcome.signers = verification.signatures
        outcome.isEncrypted = verification.encryption != nil

        if verification.signatures.isEmpty, let data = payload, !data.isEmpty,
           let nested = try? rnp.verifyDetailed(data), !nested.signatures.isEmpty
        {
            payload = nested.payload
            outcome.signers = nested.signatures
        }

        let meaningful = outcome.isEncrypted || !outcome.signers.isEmpty
        outcome.processedAny = meaningful
        return meaningful ? (payload, outcome) : (nil, outcome)
    }

    // MARK: - Small helpers

    /// Builds security information from a decode outcome, resolving signer
    /// user IDs against the keyring.
    private func securityInformation(for outcome: DecodeOutcome, rnp: Rnp) -> SecurityInformation {
        let signers = signerInfos(outcome.signers, rnp: rnp)
        return SecurityInformation(
            isEncrypted: outcome.isEncrypted,
            signers: signers,
            signingError: outcome.signingError ?? signingError(for: signers),
            encryptionError: outcome.encryptionError
        )
    }

    /// Envelope headers of an entity: everything except Content-* headers.
    private func nonContentHeaders(of entity: MimeMessage) -> [MimeMessage.Header] {
        entity.headers.filter { !$0.name.lowercased().hasPrefix("content-") }
    }

    /// Replaces (or appends) the Content-Transfer-Encoding header.
    private func replaceTransferEncoding(
        in headers: inout [MimeMessage.Header],
        with value: String
    ) {
        if let index = headers.firstIndex(where: {
            $0.name.caseInsensitiveCompare("Content-Transfer-Encoding") == .orderedSame
        }) {
            headers[index] = MimeMessage.Header(name: headers[index].name, value: value)
        }
    }
}
