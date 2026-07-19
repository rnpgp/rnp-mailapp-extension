//
//  MimeCorpusTests.swift
//  swift-rnp
//
//  Crash-regression test for the MIME parser against a small fixture corpus.
//

import XCTest
@testable import MailSecurityEngine

final class MimeCorpusTests: XCTestCase {
    private let fixtureNames = [
        "deep-nesting",
        "broken-boundary",
        "huge-header",
        "mixed-eols",
    ]

    func testCorpusParsesWithoutCrashing() throws {
        let bundle = Bundle.module
        for name in fixtureNames {
            guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/mime-corpus")
            else {
                XCTFail("Missing corpus fixture: \(name).txt")
                continue
            }

            let data = try Data(contentsOf: url)
            let message = MimeMessage.parse(data)

            // The only invariant is that parsing does not crash. We do exercise
            // the common accessors to catch lazy crashes.
            _ = message.headers
            _ = message.body
            _ = message.parts
            _ = message.decodedBody()
        }
    }
}
