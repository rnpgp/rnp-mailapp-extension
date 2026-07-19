//
//  RnpKey.swift
//  swift-rnp
//
//  Handle to a key held by an `Rnp` context's keyrings.
//

import CRnp
import Foundation

/// A key located in (or generated into) an `Rnp` context's keyrings.
///
/// Wraps `rnp_key_handle_t`; the handle is released when the instance is
/// deallocated. Instances are obtained via `Rnp.locateKey` / `Rnp.requireKey`.
public final class RnpKey {
    internal let handle: rnp_key_handle_t

    internal init(handle: rnp_key_handle_t) {
        self.handle = handle
    }

    deinit {
        rnp_key_handle_destroy(handle)
    }

    /// Uppercase hexadecimal fingerprint of the key.
    public var fingerprint: String {
        get throws {
            var fprint: UnsafeMutablePointer<CChar>?
            try rnpCheck(rnp_key_get_fprint(handle, &fprint), operation: "key fingerprint")
            return try rnpTakeString(fprint, operation: "key fingerprint")
        }
    }

    /// All user IDs bound to the key.
    public var userIDs: [String] {
        get throws {
            var count = 0
            try rnpCheck(rnp_key_get_uid_count(handle, &count), operation: "key uid count")
            return try (0 ..< count).map { index in
                var uid: UnsafeMutablePointer<CChar>?
                try rnpCheck(rnp_key_get_uid_at(handle, index, &uid), operation: "key uid")
                return try rnpTakeString(uid, operation: "key uid")
            }
        }
    }

    /// The key's primary user ID.
    public var primaryUserID: String {
        get throws {
            var uid: UnsafeMutablePointer<CChar>?
            try rnpCheck(rnp_key_get_primary_uid(handle, &uid), operation: "key primary uid")
            return try rnpTakeString(uid, operation: "key primary uid")
        }
    }

    /// Whether the secret key material is available in the secret keyring.
    public var hasSecret: Bool {
        get throws {
            var result = false
            try rnpCheck(rnp_key_have_secret(handle, &result), operation: "key have secret")
            return result
        }
    }

    /// Exports the key (including its subkeys) in OpenPGP format.
    ///
    /// - Parameters:
    ///   - secret: export the secret key material instead of the public part.
    ///   - armored: ASCII-armor the exported data.
    /// - Returns: the exported key data.
    public func exportKey(secret: Bool = false, armored: Bool = true) throws -> Data {
        var flags: UInt32 = RNP_KEY_EXPORT_SUBKEYS
        flags |= secret ? RNP_KEY_EXPORT_SECRET : RNP_KEY_EXPORT_PUBLIC
        if armored {
            flags |= RNP_KEY_EXPORT_ARMORED
        }
        let output = try MemoryOutput()
        try rnpCheck(rnp_key_export(handle, output.handle, flags), operation: "key export")
        return try output.readData()
    }
}
