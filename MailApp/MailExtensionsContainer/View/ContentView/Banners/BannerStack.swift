//
//  BannerStack.swift
//  RNP
//
//  Stacked banners for keyring-locked, import errors, trust conflicts,
//  and expiry warnings. Extracted from ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

extension ContentView {
    @ViewBuilder
    var bannerStack: some View {
        let conflicts = model.trustConflicts
        let expiry = model.expiryReport()
        if model.keyringLocked || !conflicts.isEmpty || !expiry.isEmpty || model.importError != nil {
            VStack(spacing: RnpSpacing.xs) {
                if model.keyringLocked {
                    BannerView(
                        icon: "lock.fill",
                        tint: RnpBrand.critical,
                        text: "banner.keyringLocked".localized,
                        actionTitle: "banner.keyringLocked.unlock",
                        action: { model.currentSheet = .keyringUnlock },
                        actionIdentifier: "contentview.keyring-locked.unlock"
                    )
                    .accessibilityIdentifier("contentview.keyring-locked-banner")
                }
                if let importError = model.importError {
                    RnpInlineError(
                        message: importError,
                        recoverySuggestion: "error.importFailed.recovery".localized,
                        onDismiss: { model.importError = nil }
                    )
                    .accessibilityIdentifier("contentview.import-error")
                }
                if let first = conflicts.first {
                    let suffix = conflicts.count > 1 ? " (and \(conflicts.count - 1) more)" : ""
                    BannerView(
                        icon: "exclamationmark.shield.fill",
                        tint: RnpBrand.critical,
                        text: String(format: "banner.trustConflict".localized, first.email + suffix),
                        actionTitle: "detail.keepOldBinding",
                        action: { model.rejectConflict(first) },
                        actionIdentifier: "contentview.trust-conflict-keep-old"
                    )
                    .accessibilityIdentifier("contentview.trust-conflict-banner")
                }
                if let first = expiry.first {
                    let suffix = expiry.count > 1 ? " (and \(expiry.count - 1) more)" : ""
                    let format = first.isExpired ? "banner.expired" : "banner.expiringSoon"
                    BannerView(
                        icon: first.isExpired ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                        tint: first.isExpired ? RnpBrand.critical : RnpBrand.unverified,
                        text: String(format: format.localized, first.userID + suffix)
                    )
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
