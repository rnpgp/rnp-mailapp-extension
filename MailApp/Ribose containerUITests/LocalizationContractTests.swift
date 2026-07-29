//
//  LocalizationContractTests.swift
//  Ribose containerUITests
//
//  Build-time guard against the recurring "missing key in
//  Localizable.xcstrings" bug class. Scans the host app's Swift sources
//  for `.localized` references and asserts every referenced key exists
//  in the catalog.
//
//  Limitation: scans only the host app's own sources. References from
//  the SPM dependency `swift-rnp` (which resolves `.localized` against
//  the host's `Bundle.main` at runtime) are not checked here — that
//  requires a parallel test in the swift-rnp repo. Even partial
//  coverage catches the bug class for code we own.
//

import XCTest

final class LocalizationContractTests: XCTestCase {
    func testEveryLocalizedKeyReferencedInHostSourcesExistsInCatalog() throws {
        let testFile = URL(fileURLWithPath: #file)
        // MailApp/Ribose containerUITests/LocalizationContractTests.swift → MailApp/
        let mailAppDir = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let xcstringsURL = mailAppDir
            .appendingPathComponent("MailExtensionsContainer")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")

        guard FileManager.default.fileExists(atPath: xcstringsURL.path) else {
            XCTFail("Localizable.xcstrings not found at \(xcstringsURL.path)")
            return
        }

        let catalogKeys = try Self.loadCatalogKeys(at: xcstringsURL)
        let referencedKeys = try Self.collectLocalizedReferences(under: mailAppDir)

        let missing = referencedKeys.filter { !catalogKeys.contains($0) }
        if !missing.isEmpty {
            XCTFail("""
            \(missing.count) localization key(s) referenced in host sources are \
            missing from \(xcstringsURL.lastPathComponent):
            \(missing.sorted().joined(separator: "\n"))

            Add them to MailApp/MailExtensionsContainer/Resources/Localizable.xcstrings \
            (Xcode String Catalog). SwiftUI renders missing keys as raw key text \
            at runtime.
            """)
        }
    }

    // MARK: - Helpers

    private static func loadCatalogKeys(at url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = object?["strings"] as? [String: Any] ?? [:]
        return Set(strings.keys)
    }

    /// Walks `root` recursively, reads every `.swift` file outside build
    /// directories, and extracts string literals followed by `.localized`.
    private static func collectLocalizedReferences(under root: URL) throws -> Set<String> {
        var keys = Set<String>()
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )!

        for case let url as URL in enumerator {
            // Skip build output directories.
            if url.pathExtension == "build" || url.path.contains("/Build/") {
                continue
            }
            guard url.pathExtension == "swift" else { continue }

            let source = try String(contentsOf: url, encoding: .utf8)
            keys.formUnion(Self.scanDotLocalized(in: source))
        }
        return keys
    }

    /// Matches `"some.key".localized` (with a leading non-backslash quote so
    /// interpolated strings are skipped). The captured group is the key.
    private static func scanDotLocalized(in source: String) -> Set<String> {
        var keys = Set<String>()
        let pattern = #"(?<!\\)"([A-Za-z][A-Za-z0-9_.\-]+)"\.localized"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return keys }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: source, options: [], range: range) where match.numberOfRanges > 1 {
            keys.insert(ns.substring(with: match.range(at: 1)))
        }
        return keys
    }
}
