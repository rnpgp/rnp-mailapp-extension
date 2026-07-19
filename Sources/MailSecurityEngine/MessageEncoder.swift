//
//  MessageEncoder.swift
//  swift-rnp
//
//  Encoding side of the mail security engine: wraps an outgoing RFC 822
//  message into PGP/MIME (RFC 3156) or inline-PGP form.
//

import Foundation
import Rnp

extension MailSecurityEngine {
    /// Encodes a message in PGP/MIME form (RFC 3156 sections 4 and 5).
    ///
    /// The protected content is the original message's MIME entity: its
    /// Content-* headers and body are moved into the protected part, while
    /// envelope headers (From, To, Subject, ...) stay at the top level.
    /// Signed data is CRLF-canonicalized as required by RFC 3156.
    func encodePGPMime(
        _ request: EncodingRequest,
        signer: RnpKey?,
        recipients: [RnpKey],
        rnp: Rnp
    ) throws -> EncodedMessage {
        let parsed = MimeMessage.parse(request.message)
        let eol: EndOfLine = .crlf

        var topHeaders: [MimeMessage.Header] = []
        var contentHeaders: [MimeMessage.Header] = []
        for header in parsed.headers {
            if header.name.lowercased().hasPrefix("content-") {
                contentHeaders.append(header)
            } else {
                topHeaders.append(header)
            }
        }
        if contentHeaders.isEmpty {
            contentHeaders = [MimeMessage.Header(
                name: "Content-Type",
                value: "text/plain; charset=\"utf-8\""
            )]
        }
        if !topHeaders.contains(where: { $0.name.caseInsensitiveCompare("MIME-Version") == .orderedSame }) {
            topHeaders.append(MimeMessage.Header(name: "MIME-Version", value: "1.0"))
        }

        // The MIME entity being protected.
        var entity = Data()
        for header in contentHeaders {
            entity.append(Data("\(header.name): \(header.value)".utf8))
            entity.append(eol.data)
        }
        entity.append(eol.data)
        entity.append(parsed.body)

        let boundary = makeBoundary(avoiding: entity)

        var body = Data()
        let topLevelType: MimeMessage.Header
        if request.encrypt {
            // Sign inside the encryption envelope: only the recipient can
            // both read and verify the message.
            var plaintext = entity
            if request.sign, let signer {
                plaintext = try rnp.sign(entity, with: signer, armored: false)
            }
            let ciphertext = try rnp.encrypt(plaintext, for: recipients, armored: true)
            appendLine("--\(boundary)", to: &body, eol: eol)
            appendLine("Content-Type: application/pgp-encrypted", to: &body, eol: eol)
            appendLine("", to: &body, eol: eol)
            appendLine("Version: 1", to: &body, eol: eol)
            appendLine("", to: &body, eol: eol)
            appendLine("--\(boundary)", to: &body, eol: eol)
            appendLine("Content-Type: application/octet-stream; name=\"encrypted.asc\"", to: &body, eol: eol)
            appendLine("Content-Description: OpenPGP encrypted message", to: &body, eol: eol)
            appendLine("Content-Disposition: inline; filename=\"encrypted.asc\"", to: &body, eol: eol)
            appendLine("", to: &body, eol: eol)
            body.append(ciphertext)
            appendPartEndOfLine(&body, eol: eol)
            appendLine("--\(boundary)--", to: &body, eol: eol)
            topLevelType = MimeMessage.Header(
                name: "Content-Type",
                value: "multipart/encrypted; protocol=\"application/pgp-encrypted\"; boundary=\"\(boundary)\""
            )
        } else if request.sign, let signer {
            let signedEntity = MimeMessage.crlfNormalized(entity)
            let signature = try rnp.signDetached(signedEntity, with: signer, armored: true)
            appendLine("--\(boundary)", to: &body, eol: eol)
            body.append(signedEntity)
            appendPartEndOfLine(&body, eol: eol)
            appendLine("--\(boundary)", to: &body, eol: eol)
            appendLine("Content-Type: application/pgp-signature; name=\"signature.asc\"", to: &body, eol: eol)
            appendLine("Content-Description: OpenPGP digital signature", to: &body, eol: eol)
            appendLine("Content-Disposition: attachment; filename=\"signature.asc\"", to: &body, eol: eol)
            appendLine("", to: &body, eol: eol)
            body.append(signature)
            appendPartEndOfLine(&body, eol: eol)
            appendLine("--\(boundary)--", to: &body, eol: eol)
            topLevelType = MimeMessage.Header(
                name: "Content-Type",
                value: "multipart/signed; micalg=\"pgp-sha256\"; protocol=\"application/pgp-signature\"; boundary=\"\(boundary)\""
            )
        } else {
            // Unreachable: encode() rejects requests with both flags off and
            // PGP/MIME encryption without a recipient list.
            preconditionFailure("PGP/MIME encode without sign or encrypt")
        }

        return EncodedMessage(
            rawData: serialize(headers: topHeaders + [topLevelType], body: body, eol: eol),
            isSigned: request.sign,
            isEncrypted: request.encrypt
        )
    }

    /// Encodes a message in inline-PGP form: the body text is replaced by an
    /// ASCII-armored OpenPGP message. Only single-part messages can be
    /// protected this way.
    func encodeInline(
        _ request: EncodingRequest,
        signer: RnpKey?,
        recipients: [RnpKey],
        rnp: Rnp
    ) throws -> EncodedMessage {
        let parsed = MimeMessage.parse(request.message)
        if let contentType = parsed.contentType, contentType.isMultipart {
            throw MailSecurityError.multipartNotSupportedForInline
        }

        // The protected payload is the decoded body text.
        var payload = parsed.decodedBody()
        if request.sign, let signer {
            payload = try rnp.sign(payload, with: signer, armored: !request.encrypt)
        }
        if request.encrypt {
            payload = try rnp.encrypt(payload, for: recipients, armored: true)
        }

        // The armored payload is 7bit-clean ASCII.
        var headers = parsed.headers
        if let index = headers.firstIndex(where: {
            $0.name.caseInsensitiveCompare("Content-Transfer-Encoding") == .orderedSame
        }) {
            headers[index] = MimeMessage.Header(name: "Content-Transfer-Encoding", value: "7bit")
        }
        return EncodedMessage(
            rawData: serialize(headers: headers, body: payload, eol: parsed.eol),
            isSigned: request.sign,
            isEncrypted: request.encrypt
        )
    }

    // MARK: - Building blocks

    /// Generates a multipart boundary that does not occur in the content.
    func makeBoundary(avoiding content: Data) -> String {
        var boundary: String
        repeat {
            boundary = "----rnp-boundary-\(UUID().uuidString)"
        } while content.range(of: Data(boundary.utf8)) != nil
        return boundary
    }

    func appendLine(_ line: String, to data: inout Data, eol: EndOfLine) {
        data.append(Data(line.utf8))
        data.append(eol.data)
    }

    /// Appends exactly one EOL after part content, ahead of a boundary
    /// delimiter. This is unconditional on purpose: the EOL preceding a
    /// delimiter belongs to the delimiter (RFC 2046 5.1.1), so content that
    /// itself ends with an EOL must be followed by two. Skipping the append
    /// would corrupt byte-exact part extraction (and signature
    /// verification) for such content.
    func appendPartEndOfLine(_ data: inout Data, eol: EndOfLine) {
        data.append(eol.data)
    }
}
