//
//  PseudoLocalization.swift
//  RNP
//
//  Pseudo-localization: transforms every English string into a
//  longer, bracketed, accented variant that exposes truncation and
//  layout overflow before real translators do. Standard technique
//  used by Android, Chrome, Mozilla.
//
//  Usage in tests:
//
//      func test_keyListView_pseudoLocalized() throws {
//          try SnapshotHarness.assertSnapshot(
//              of: KeysListView(...).environment(\.locale, PseudoLocalization.locale)
//                .environment(\.pseudoLocalized, true),
//              named: "KeysListView-pseudo",
//              size: CGSize(width: 800, height: 400)
//          )
//      }
//
//  Or use the bundled SwiftUI modifier:
//
//      view.pseudoLocalized()
//
//  See TODO.complete/24-localization-qa.md.
//

import SwiftUI

enum PseudoLocalization {

    /// Locale identifier that doesn't collide with real locales. Tests
    /// can use this to opt a view into pseudo-localized rendering.
    static let locale = Locale(identifier: "qpa")

    /// Lengthens every ASCII letter by ~30% and accents it, then
    /// wraps the whole string in brackets. Mirrors Mozilla's
    /// "accented + lengthy" pseudo-localization.
    ///
    /// Example: "Hello" → "[Ħḗḗḗḗḗłłööö]"  (length grows ~30%)
    static func transform(_ source: String) -> String {
        var out = ""
        for char in source {
            if let expanded = expansionMap[char] {
                out += expanded
            } else {
                out.append(char)
            }
        }
        // Pad to ~1.3x original length to mimic verbose locales (German, Russian).
        let target = Int(Double(source.count) * 1.3)
        while out.count < target {
            out.append("~")
        }
        return "[" + out + "]"
    }

    /// One-character → multi-character mapping. The replacements are
    /// visually distinctive (accents, doubled letters) so a glance at
    /// a screenshot reveals whether the layout accommodates them.
    private static let expansionMap: [Character: String] = [
        "a": "ḗ", "b": "ḅ", "c": "ç", "d": "ḍ", "e": "ḗ", "f": "ḟ",
        "g": "ǧ", "h": "ħ", "i": "ī", "j": "ǰ", "k": "ḳ", "l": "ḽ",
        "m": "ṁ", "n": "ṇ", "o": "ö", "p": "ṗ", "q": "ɋ", "r": "ṛ",
        "s": "š", "t": "ṭ", "u": "ü", "v": "ṽ", "w": "ẇ", "x": "ẋ",
        "y": "ẏ", "z": "ẑ",
        "A": "ḗ", "B": "ḅ", "C": "Ç", "D": "Ḍ", "E": "ḗ", "F": "Ḟ",
        "G": "Ǧ", "H": "Ħ", "I": "Ī", "J": "Ɉ", "K": "Ḳ", "L": "Ḻ",
        "M": "Ṁ", "N": "Ṇ", "O": "Ö", "P": "Ṗ", "Q": "Ɋ", "R": "Ṛ",
        "S": "Š", "T": "Ṭ", "U": "Ü", "V": "Ṽ", "W": "Ẇ", "X": "Ẋ",
        "Y": "Ẏ", "Z": "Ẑ"
    ]
}

private struct PseudoLocalizedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// True when the view tree should pseudo-localize its strings.
    var pseudoLocalized: Bool {
        get { self[PseudoLocalizedKey.self] }
        set { self[PseudoLocalizedKey.self] = newValue }
    }
}

extension View {
    /// Marks this view tree as pseudo-localized. Strings displayed via
    /// `Text(LocalizedStringKey)` won't auto-translate (SwiftUI uses
    /// the bundle lookup), so this modifier is mostly a marker for
    /// tests that want to detect overflow via `PseudoLocalization.transform`.
    func pseudoLocalized() -> some View {
        environment(\.pseudoLocalized, true)
            .environment(\.locale, PseudoLocalization.locale)
    }
}
