//
//  LocalizationTests.swift
//  swift-rnp
//
//  Validation for the Localizable.xcstrings string catalog.
//

import XCTest

final class LocalizationTests: XCTestCase {
    private var catalogURL: URL {
        // Tests/RnpMailUITests/LocalizationTests.swift
        //   -> Swift-Rnp/MailExtensionsContainer/Resources/Localizable.xcstrings
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Swift-Rnp/MailExtensionsContainer/Resources/Localizable.xcstrings")
    }

    private func loadCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw NSError(domain: "LocalizationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Catalog is not a JSON dictionary"])
        }
        return dict
    }

    func testCatalogIsValidJSON() throws {
        let catalog = try loadCatalog()
        XCTAssertNotNil(catalog["sourceLanguage"] as? String)
        XCTAssertNotNil(catalog["strings"] as? [String: Any])
    }

    func testAllKeysHaveEnglishTranslation() throws {
        let catalog = try loadCatalog()
        guard let strings = catalog["strings"] as? [String: Any] else {
            XCTFail("Missing strings object")
            return
        }
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let en = localizations["en"] as? [String: Any],
                  let stringUnit = en["stringUnit"] as? [String: Any],
                  let translatedValue = stringUnit["value"] as? String
            else {
                XCTFail("Key '\(key)' is missing an English translation")
                continue
            }
            XCTAssertFalse(translatedValue.isEmpty, "Key '\(key)' has an empty English translation")
        }
    }

    func testNoEmptyStringValues() throws {
        let catalog = try loadCatalog()
        guard let strings = catalog["strings"] as? [String: Any] else {
            XCTFail("Missing strings object")
            return
        }
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any]
            else {
                continue
            }
            for (lang, loc) in localizations {
                guard let locDict = loc as? [String: Any],
                      let stringUnit = locDict["stringUnit"] as? [String: Any],
                      let translatedValue = stringUnit["value"] as? String
                else {
                    continue
                }
                XCTAssertFalse(translatedValue.isEmpty, "Key '\(key)' has an empty translation for language '\(lang)'")
            }
        }
    }

    func testSourceLanguageIsEnglish() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
    }
}
