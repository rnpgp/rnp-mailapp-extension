//
//  String+Localization.swift
//  swift-rnp
//
//  Convenience accessor for strings stored in the RnpMailUI String Catalog.
//

import Foundation

extension String {
    /// Returns the localized string for this key using the default `Localizable`
    /// table bundled with `RnpMailUI`.
    public var localized: String {
        String(localized: String.LocalizationValue(self))
    }
}
