//
//  SparkleBootstrap.swift
//  RNP
//
//  Wires the Sparkle 2 update framework. Sparkle checks the appcast
//  feed (Info.plist `SUFeedURL`) on launch and on a weekly timer;
//  when an update is found, it presents a system prompt and installs
//  the signed + notarized DMG.
//
//  App Store builds do NOT link Sparkle — App Store has its own update
//  channel. Gate this file behind `#if !APPSTORE` once the AppStore
//  config defines that flag.
//

import Sparkle
import SwiftUI

/// Owns the `SPUStandardUpdaterController`. Created once at app launch
/// and kept alive for the process lifetime; the controller manages its
/// own scheduling.
final class UpdaterController: ObservableObject {
    private var controller: SPUStandardUpdaterController?

    /// User-tunable: whether Sparkle is allowed to check for updates
    /// automatically. Mirrored to `UserDefaults` so the Tools hub can
    /// bind to it.
    @AppStorage("sparkle.autoUpdateChecks") var autoUpdateChecks: Bool = true {
        didSet {
            controller?.updater.automaticallyChecksForUpdates = autoUpdateChecks
        }
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller?.updater.automaticallyChecksForUpdates = autoUpdateChecks
        controller?.updater.updateCheckInterval = 60 * 60 * 24 * 7 // weekly
    }

    /// Manual "check now" entry point. Wired from the app menu and the
    /// Tools hub.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Tear down before app termination. Sparkle handles this itself in
    /// most cases, but explicit is better than implicit.
    deinit {
        controller?.updater.automaticallyChecksForUpdates = false
    }
}
