//
//  MessageSecurityCoreTests.swift
//  swift-rnp
//
//  Unit tests for the MailKit-independent message-security core.
//

import XCTest
@testable import MailSecurityEngine

final class MessageSecurityCoreTests: XCTestCase {
    private static let alice = "Alice <alice@example.com>"
    private static let aliceEmail = "alice@example.com"
    private static let bob = "Bob <bob@example.com>"
    private static let bobEmail = "bob@example.com"
    private static let password = "test-password"

    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in tempDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirectories = []
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-rnp-tests")
            .appendingPathComponent(UUID().uuidString)
        tempDirectories.append(url)
        return url
    }

    private func makeEngine(keys userIDs: [String] = []) throws -> MailSecurityEngine {
        let engine = try MailSecurityEngine(
            directory: makeTempDirectory(),
            passphraseProvider: { _ in Self.password }
        )
        for userID in userIDs {
            try engine.keyManager.generateKey(userID: userID, algorithm: .ecdsa)
        }
        return engine
    }

    private func makeCore(keys userIDs: [String] = []) throws -> MessageSecurityCore {
        MessageSecurityCore(engine: try makeEngine(keys: userIDs))
    }

    private func plainMessage(
        from: String = "alice@example.com",
        to: String = "bob@example.com",
        body: String = "Hello, Bob!"
    ) -> Data {
        let lines = [
            "From: \(from)",
            "To: \(to)",
            "Subject: core test",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=\"utf-8\"",
        ]
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }

    // MARK: - Mocks

    private struct MockMessage: MailMessage {
        var rawData: Data?
        var fromAddress: String
        var recipientAddresses: [String]
        var isSending: Bool
    }

    private struct MockComposeContext: MailComposeContext {
        var shouldSign: Bool
        var shouldEncrypt: Bool
    }

    private struct MockSigner: MailMessageSigner {
        var signerEmailAddresses: [String]
        var signerLabel: String
        var context: Data
    }

    // MARK: - getEncodingStatus

    func testGetEncodingStatusWithKey() throws {
        let core = try makeCore(keys: [Self.alice])
        let message = MockMessage(
            rawData: nil,
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: true
        )
        let context = MockComposeContext(shouldSign: true, shouldEncrypt: false)
        let status = core.getEncodingStatus(for: message, composeContext: context)

        XCTAssertTrue(status.canSign)
        XCTAssertFalse(status.canEncrypt)
        XCTAssertEqual(status.addressesFailingEncryption, [Self.bobEmail])
    }

    func testGetEncodingStatusWithoutKey() throws {
        let core = try makeCore()
        let message = MockMessage(
            rawData: nil,
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: true
        )
        let context = MockComposeContext(shouldSign: true, shouldEncrypt: true)
        let status = core.getEncodingStatus(for: message, composeContext: context)

        XCTAssertFalse(status.canSign)
        XCTAssertFalse(status.canEncrypt)
        XCTAssertEqual(status.addressesFailingEncryption, [Self.bobEmail])
    }

    // MARK: - encode

    func testEncodeSignOnly() throws {
        let core = try makeCore(keys: [Self.alice])
        let message = MockMessage(
            rawData: plainMessage(),
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: true
        )
        let context = MockComposeContext(shouldSign: true, shouldEncrypt: false)
        let result = core.encode(message, composeContext: context)

        XCTAssertNotNil(result.encodedMessage)
        XCTAssertTrue(result.encodedMessage?.isSigned ?? false)
        XCTAssertFalse(result.encodedMessage?.isEncrypted ?? true)
        XCTAssertNil(result.signingError)
        XCTAssertNil(result.encryptionError)
    }

    func testEncodeNotSendingReturnsNoEncoding() throws {
        let core = try makeCore(keys: [Self.alice])
        let message = MockMessage(
            rawData: plainMessage(),
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: false
        )
        let context = MockComposeContext(shouldSign: true, shouldEncrypt: false)
        let result = core.encode(message, composeContext: context)

        XCTAssertNil(result.encodedMessage)
        XCTAssertNil(result.signingError)
        XCTAssertNil(result.encryptionError)
    }

    func testEncodeMissingSecretKeyReturnsSigningError() throws {
        let core = try makeCore()
        let message = MockMessage(
            rawData: plainMessage(),
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: true
        )
        let context = MockComposeContext(shouldSign: true, shouldEncrypt: false)
        let result = core.encode(message, composeContext: context)

        XCTAssertNil(result.encodedMessage)
        XCTAssertNotNil(result.signingError)
        XCTAssertNil(result.encryptionError)
    }

    func testEncodeMissingRecipientKeyReturnsEncryptionError() throws {
        let core = try makeCore(keys: [Self.alice])
        let message = MockMessage(
            rawData: plainMessage(),
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: true
        )
        let context = MockComposeContext(shouldSign: false, shouldEncrypt: true)
        let result = core.encode(message, composeContext: context)

        XCTAssertNil(result.encodedMessage)
        XCTAssertNil(result.signingError)
        XCTAssertNotNil(result.encryptionError)
    }

    // MARK: - decodedMessage

    func testDecodedMessagePlainReturnsNil() throws {
        let core = try makeCore(keys: [Self.alice])
        let decoded = core.decodedMessage(forMessageData: plainMessage())
        XCTAssertNil(decoded)
    }

    func testDecodedMessageSignedReturnsSigners() throws {
        let aliceEngine = try makeEngine(keys: [Self.alice])
        let bobEngine = try makeEngine(keys: [Self.bob])

        // Bob needs Alice's public key to verify the signature.
        let aliceFingerprint = try XCTUnwrap(aliceEngine.keyManager.listKeys().first?.fingerprint)
        let alicePublicKey = try aliceEngine.keyManager.exportKey(fingerprint: aliceFingerprint)
        try bobEngine.keyManager.importKeys(alicePublicKey)

        let aliceCore = MessageSecurityCore(engine: aliceEngine)
        let bobCore = MessageSecurityCore(engine: bobEngine)

        let message = MockMessage(
            rawData: plainMessage(),
            fromAddress: Self.aliceEmail,
            recipientAddresses: [Self.bobEmail],
            isSending: true
        )
        let context = MockComposeContext(shouldSign: true, shouldEncrypt: false)
        let result = aliceCore.encode(message, composeContext: context)
        let encoded = try XCTUnwrap(result.encodedMessage)

        let decoded = try XCTUnwrap(bobCore.decodedMessage(forMessageData: encoded.rawData))
        XCTAssertEqual(decoded.securityInformation.signers.count, 1)
        XCTAssertFalse(decoded.securityInformation.isEncrypted)
        XCTAssertNil(decoded.securityInformation.signingError)

        let signer = try XCTUnwrap(decoded.securityInformation.signers.first)
        XCTAssertEqual(signer.emailAddresses, [Self.alice])
        XCTAssertEqual(signer.signatureLabel, Self.alice)

        let signerContext = try XCTUnwrap(bobCore.signerContext(for: signer))
        XCTAssertEqual(signerContext.status, "valid")
        XCTAssertNotNil(signerContext.fingerprint)
    }

    // MARK: - signerContext

    func testSignerContextEmptyReturnsNil() throws {
        let core = try makeCore()
        let signer = MockSigner(signerEmailAddresses: [], signerLabel: "", context: Data())
        XCTAssertNil(core.signerContext(for: signer))
    }

    func testSignerContextInvalidJSONReturnsNil() throws {
        let core = try makeCore()
        let signer = MockSigner(signerEmailAddresses: [], signerLabel: "", context: Data("not json".utf8))
        XCTAssertNil(core.signerContext(for: signer))
    }
}
