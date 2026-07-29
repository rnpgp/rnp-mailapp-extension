//
//  SheetRouter.swift
//  RNP for Mail
//
//  Single source of truth for "which sheet is presented in the main window
//  right now". Replaces the NotificationCenter.Name posts that menu items
//  used to fire for the licenses / keyserver / security sheets, and provides
//  the seam future PRs can use to migrate the 12 @Published var showXxx
//  booleans on ContentViewModel.
//

import Foundation

@MainActor
final class SheetRouter: ObservableObject {
    @Published var current: Sheet?

    func present(_ sheet: Sheet) { current = sheet }
    func dismiss() { current = nil }
}

/// Sheets the container app's main window can present. Associated values
/// carry only what's needed to construct the sheet at presentation time;
/// form state that changes while the sheet is open (e.g. fetchQuery,
/// revokeReason) continues to live on ContentViewModel.
enum Sheet: Hashable, Identifiable {
    case licenses
    case keyServerSettings
    case securitySettings

    var id: Self { self }
}
