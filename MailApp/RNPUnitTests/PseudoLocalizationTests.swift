import XCTest
@testable import RNP

final class PseudoLocalizationTests: XCTestCase {

    func test_transform_wrapsInBrackets() {
        let result = PseudoLocalization.transform("Hello")
        XCTAssertTrue(result.hasPrefix("["))
        XCTAssertTrue(result.hasSuffix("]"))
    }

    func test_transform_lengthensByAtLeast30Percent() {
        let original = "Hello World"
        let transformed = PseudoLocalization.transform(original)
        XCTAssertGreaterThan(transformed.count, Int(Double(original.count) * 1.2))
    }

    func test_transform_handlesEmptyString() {
        XCTAssertEqual(PseudoLocalization.transform(""), "[]")
    }

    func test_transform_isDeterministic() {
        let input = "Test 123"
        XCTAssertEqual(PseudoLocalization.transform(input), PseudoLocalization.transform(input))
    }
}
