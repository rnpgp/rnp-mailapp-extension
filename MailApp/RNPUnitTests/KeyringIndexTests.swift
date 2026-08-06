import XCTest
@testable import RNP

final class KeyringIndexTests: XCTestCase {

    func test_emptyIndex_returnsEmptyForAnyQuery() {
        let index = KeyringIndex()
        XCTAssertTrue(index.search("anything").isEmpty)
        XCTAssertTrue(index.search("").isEmpty)
    }

    func test_singleKey_insertAndSearchByUserID() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "ABCDEF0123456789", userIDs: ["Alice <alice@example.com>"]))
        XCTAssertEqual(index.search("alice"), ["ABCDEF0123456789"])
    }

    func test_searchByEmailDomain_matchesAllKeysInDomain() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "AAAA", userIDs: ["Alice <a@example.com>"]))
        index.insert(.init(fingerprint: "BBBB", userIDs: ["Bob <b@example.com>"]))
        index.insert(.init(fingerprint: "CCCC", userIDs: ["Eve <eve@evil.com>"]))
        XCTAssertEqual(Set(index.search("example.com")), ["AAAA", "BBBB"])
    }

    func test_fingerprintSubstring_matches() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "ABCDEFGHIJ123456", userIDs: []))
        XCTAssertEqual(index.search("CDEF"), ["ABCDEFGHIJ123456"])
        XCTAssertEqual(index.search("ABCD"), ["ABCDEFGHIJ123456"])
        XCTAssertEqual(index.search("3456"), ["ABCDEFGHIJ123456"])
    }

    func test_remove_erasesKeyFromAllTokens() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "AAAA", userIDs: ["Alice"]))
        index.insert(.init(fingerprint: "BBBB", userIDs: ["Alice"]))
        XCTAssertEqual(Set(index.search("Alice")), ["AAAA", "BBBB"])
        index.remove(fingerprint: "AAAA")
        XCTAssertEqual(index.search("Alice"), ["BBBB"])
    }

    func test_insert_isIdempotent() {
        var index = KeyringIndex()
        let key = KeyringIndex.IndexedKey(fingerprint: "AAAA", userIDs: ["Alice"])
        index.insert(key)
        index.insert(key)
        XCTAssertEqual(index.search("Alice").filter { $0 == "AAAA" }.count, 1)
    }

    func test_rebuild_replacesEntireIndex() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "OLD1", userIDs: ["Alice"]))
        index.rebuild(from: [
            .init(fingerprint: "NEW1", userIDs: ["Bob"]),
            .init(fingerprint: "NEW2", userIDs: ["Carol"])
        ])
        XCTAssertTrue(index.search("Alice").isEmpty)
    }

    func test_multiTokenQuery_intersects() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "AAAA", userIDs: ["Alice Wang"]))
        index.insert(.init(fingerprint: "BBBB", userIDs: ["Alice Smith"]))
        XCTAssertEqual(index.search("Alice Wang"), ["AAAA"])
    }

    func test_emptyQuery_returnsAllKnownFingerprints() {
        var index = KeyringIndex()
        index.insert(.init(fingerprint: "AAAA", userIDs: ["Alice"]))
        index.insert(.init(fingerprint: "BBBB", userIDs: ["Bob"]))
        XCTAssertEqual(Set(index.search("")), ["AAAA", "BBBB"])
    }

    func test_tokenize_splitsOnPunctuation() {
        let tokens = KeyringIndex.tokenize("Alice <alice@example.com>")
        XCTAssertTrue(tokens.contains("alice"))
        XCTAssertTrue(tokens.contains("example"))
        XCTAssertTrue(tokens.contains("com"))
    }
}
