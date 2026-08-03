//
//  RnpLogger.swift
//  RNP
//
//  Centralized os.Logger instance. Every category the app logs through
//  has a static property here so call sites are short and consistent:
//
//    RnpLogger.fileOps.info("encrypting \(count) bytes")
//    RnpLogger.keyring.error("open failed: \(err.localizedDescription, privacy: .public)")
//    RnpLogger.engine.debug("fingerprint: \(fpr, privacy: .hash)")
//
//  Privacy rules:
//    - Public: error messages, byte counts, operation names
//    - Hash:   key fingerprints, recipient addresses (one-way)
//    - Private (default): file paths, user IDs — never auto-redact
//
//  See TODO.complete/21-unified-logging.md.
//

import Foundation
import os

enum RnpLogger {
    static let subsystem = "com.rnpgp.RNPForMail"

    /// Keyring load, save, lock state, key import/export.
    static let keyring = Logger(subsystem: subsystem, category: "keyring")
    /// Mail extension decode/encode, pluginkit registration state.
    static let mail    = Logger(subsystem: subsystem, category: "mail")
    /// File encrypt/decrypt/sign/verify operations.
    static let fileOps = Logger(subsystem: subsystem, category: "file-ops")
    /// SwiftUI view lifecycle, navigation, onboarding.
    static let ui      = Logger(subsystem: subsystem, category: "ui")
    /// Wrapping librnp calls — packet dumps, FFI errors.
    static let engine  = Logger(subsystem: subsystem, category: "engine")
    /// Sparkle update checks + installs.
    static let update  = Logger(subsystem: subsystem, category: "update")
    /// Backup / restore keyring archives.
    static let backup  = Logger(subsystem: subsystem, category: "backup")
}
