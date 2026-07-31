//
//  LocalizationAuditTests.swift
//  Ribose containerUITests
//
//  Asserts that the onboarding flow's must-have keys have actual
//  translations (state="translated") in every declared non-source
//  locale. The full 269-key catalog is a moving target; this test
//  covers the ~20 strings a user sees during first launch, so a
//  regression in coverage of the most visible UX is caught in CI.
//
//  The companion script scripts/i18n-status.sh prints per-locale
//  coverage for all 269 keys. Use it for translator-facing reports.
//

import XCTest

final class LocalizationAuditTests: XCTestCase {
    /// Keys that must be translated in every declared locale because
    /// they're the first thing a new user sees during onboarding.
    /// Add to this list when new onboarding strings land.
    private static let onboardingCriticalKeys: [String] = [
        // Welcome + setup
        "onboarding.welcome.title",
        "onboarding.welcome.subtitle",
        "onboarding.welcome.button",
        "onboarding.skip.button",
        "onboarding.setup.title",
        "onboarding.setup.subtitle",
        "onboarding.createKey",
        "onboarding.importKey",
        "onboarding.restoreFromBackup",
        // Generate form
        "generateForm.title",
        "generateForm.name.label",
        "generateForm.email.label",
        "generateForm.passphrase.label",
        "generateForm.confirm.label",
        "generateForm.createButton",
        // Common buttons
        "button.back",
        "button.cancel",
        "button.ok",
        "button.done",
        // Tabs / nav
        "tab.myKeys",
        "tab.recipients",
        "nav.tools",
        "title.tools"
    ]

    /// Locales declared in xcstrings (other than the source 'en').
    /// Update when Localizable.xcstrings gains a new locale.
    private static let expectedLocales: [String] = [
        "de", "es", "fr", "it", "ja", "ko", "pt", "ru", "zh-Hans", "zh-Hant"
    ]

    func testOnboardingCriticalKeysAreTranslatedInEveryDeclaredLocale() throws {
        let catalog = try Self.loadCatalog()
        let strings = catalog.strings
        var failures: [String] = []

        for key in Self.onboardingCriticalKeys {
            guard let entry = strings[key] else {
                failures.append("KEY MISSING FROM CATALOG: \(key)")
                continue
            }
            let locs = entry.localizations ?? [:]
            for locale in Self.expectedLocales {
                let unit = locs[locale]?.stringUnit
                let state = unit?.state
                let value = unit?.value
                if state != "translated" || value == nil || value?.isEmpty == true {
                    failures.append("[\(locale)] \(key) — state=\(state ?? "nil"), value=\(value ?? "nil")")
                }
            }
        }

        if !failures.isEmpty {
            XCTFail("""
            \(failures.count) onboarding-critical localization regression(s):

            \(failures.prefix(40).joined(separator: "\n"))
            \(failures.count > 40 ? "… and \(failures.count - 40) more" : "")

            Edit MailApp/MailExtensionsContainer/Resources/Localizable.xcstrings
            in Xcode (String Catalog) to fill in the missing translations, or
            run scripts/i18n-status.sh to see full per-locale coverage.
            """)
        }
    }

    /// Every locale listed in `expectedLocales` must actually be
    /// declared in the xcstrings. Catches drift if someone declares
    /// a locale in code but forgets to add it to the catalog.
    func testEveryExpectedLocaleIsPresentInCatalog() throws {
        let catalog = try Self.loadCatalog()
        let declaredLocales = Set(catalog.locales)
        for locale in Self.expectedLocales {
            XCTAssertTrue(declaredLocales.contains(locale),
                "Locale \(locale) is in expectedLocales but not declared in Localizable.xcstrings")
        }
    }

    // MARK: - Helpers

    private struct Catalog {
        let strings: [String: CatalogEntry]
        let locales: Set<String>
    }
    private struct CatalogEntry {
        let localizations: [String: LocalizationEntry]?
    }
    private struct LocalizationEntry {
        let stringUnit: StringUnit?
    }
    private struct StringUnit {
        let state: String?
        let value: String?
    }

    private static func loadCatalog() throws -> Catalog {
        let testFile = URL(fileURLWithPath: #file)
        let mailAppDir = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = mailAppDir
            .appendingPathComponent("MailExtensionsContainer")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "LocalizationAuditTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Localizable.xcstrings not found at \(url.path)"])
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rawStrings = raw["strings"] as? [String: Any] ?? [:]

        var entries: [String: CatalogEntry] = [:]
        var locales: Set<String> = []
        for (key, value) in rawStrings {
            let locs = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            var locEntries: [String: LocalizationEntry] = [:]
            for (loc, locVal) in locs {
                locales.insert(loc)
                let unit = (locVal as? [String: Any])?["stringUnit"] as? [String: Any]
                locEntries[loc] = LocalizationEntry(stringUnit: unit.map {
                    StringUnit(state: $0["state"] as? String, value: $0["value"] as? String)
                })
            }
            entries[key] = CatalogEntry(localizations: locEntries)
        }
        return Catalog(strings: entries, locales: locales)
    }
}
