//
//  MessageDecodeCache.swift
//  MailPlugin
//
//  LRU cache of decoded messages keyed by SHA-256(message bytes).
//  MailKit calls `MessageSecurityHandler.decodedMessage(forMessageData:)`
//  synchronously and may call it multiple times for the same message
//  (e.g. when the user re-opens a thread). The cache makes the second
//  call instant.
//
//  Memory pressure: NSCache handles eviction automatically; we cap at
//  50 MB of decoded payload. Cache survives Mail's process lifetime.
//
//  Thread safety: NSCache is thread-safe by contract.
//
//  See TODO.complete/07-async-decryption-queue.md.
//

import CryptoKit
import Foundation
import MailKit

/// Synchronous NSCache wrapper for the MEDecodedMessage MailKit
/// expects back. We use NSCache directly (not an actor) because
/// MailKit calls `decodedMessage(forMessageData:)` synchronously —
/// an actor would force an async hop we can't afford.
final class MessageDecodeCacheStore {
    static let shared = MessageDecodeCacheStore()

    private let cache: NSCache<NSString, MEDecodedBox> = {
        let c = NSCache<NSString, MEDecodedBox>()
        c.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return c
    }()

    private init() {}

    /// Returns the cached `MEDecodedMessage` for `data`, or nil on miss.
    func lookup(_ data: Data) -> MEDecodedMessage? {
        cache.object(forKey: Self.key(for: data) as NSString)?.value
    }

    /// Stores `medecoded` under the cache key derived from `data`.
    /// Cost is the byte size of the decoded payload — drives NSCache
    /// eviction under memory pressure.
    func store(_ data: Data, medecoded: MEDecodedMessage) {
        let cost = medecoded.rawData?.count ?? data.count
        cache.setObject(
            MEDecodedBox(value: medecoded),
            forKey: Self.key(for: data) as NSString,
            cost: cost
        )
    }

    /// Wipes the cache. Called when Mail extension unloads.
    func clear() { cache.removeAllObjects() }

    /// Stable cache key. SHA-256 is overkill for short message IDs
    /// but cheap (single block) and collision-proof.
    static func key(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// NSCache requires a class. Wraps the value-type `MEDecodedMessage`.
private final class MEDecodedBox {
    let value: MEDecodedMessage
    init(value: MEDecodedMessage) { self.value = value }
}
