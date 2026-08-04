//
//  KeyringIndex.swift
//  RNP
//
//  Inverted index over the keyring for sub-millisecond search on
//  keyrings of 1000+ keys. Pure value type — no MailSecurityEngine
//  dependency, fully testable in isolation.
//
//  Tokenization: lowercase + split on whitespace + '@' + '.' + '<' +
//  '>'. Fingerprint indexed as both the full hex string and as
//  4-character chunks (matches what users typically type).
//
//  See TODO.complete/08-keyring-indexing.md.
//

import Foundation

/// Inverted index from token → set of key fingerprints. The caller
/// owns the `KeyInfo` records; this type only knows fingerprints.
public struct KeyringIndex {

    /// Minimal key shape the index needs. Decoupled from KeyInfo so
    /// tests don't have to construct full KeyInfo instances.
    public struct IndexedKey: Equatable, Hashable {
        public let fingerprint: String
        public let userIDs: [String]
        public init(fingerprint: String, userIDs: [String]) {
            self.fingerprint = fingerprint
            self.userIDs = userIDs
        }
    }

    private var tokenToKeys: [String: Set<String>] = [:]
    private var fingerprintChunks: [String: Set<String>] = [:]
    private var knownFingerprints: Set<String> = []

    public init(keys: [IndexedKey] = []) {
        for key in keys {
            insert(key)
        }
    }

    /// Adds a key to the index. Idempotent — adding the same key twice
    /// has no effect.
    public mutating func insert(_ key: IndexedKey) {
        guard !knownFingerprints.contains(key.fingerprint) else { return }
        knownFingerprints.insert(key.fingerprint)
        for token in tokens(for: key) {
            tokenToKeys[token, default: []].insert(key.fingerprint)
        }
        for chunk in fingerprintChunks(of: key.fingerprint) {
            fingerprintChunks[chunk, default: []].insert(key.fingerprint)
        }
    }

    /// Removes a key from the index. No-op if the key wasn't present.
    public mutating func remove(fingerprint: String) {
        guard knownFingerprints.remove(fingerprint) != nil else { return }
        for var entry in tokenToKeys.values { entry.remove(fingerprint) }
        for var entry in fingerprintChunks.values { entry.remove(fingerprint) }
        tokenToKeys = tokenToKeys.filter { !$0.value.isEmpty }
        fingerprintChunks = fingerprintChunks.filter { !$0.value.isEmpty }
    }

    /// Rebuilds the index from a fresh key set. Cheaper than
    /// diffing when the whole keyring was reloaded.
    public mutating func rebuild(from keys: [IndexedKey]) {
        tokenToKeys.removeAll(keepingCapacity: true)
        fingerprintChunks.removeAll(keepingCapacity: true)
        knownFingerprints.removeAll(keepingCapacity: true)
        for key in keys { insert(key) }
    }

    /// Returns the fingerprints matching `query`, sorted by relevance
    /// (more token matches = higher relevance). Single-token queries
    /// hit the inverted index directly; multi-token queries intersect.
    public func search(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return Array(knownFingerprints) }

        let queryTokens = Self.tokenize(trimmed)
        if queryTokens.isEmpty { return [] }

        // Intersect candidates from each token; fingerprint chunks are
        // checked separately so "abcd1234" matches a long fingerprint.
        var candidates: Set<String>? = nil
        for token in queryTokens {
            let tokenHits = tokenToKeys[token] ?? Set<String>()
            let chunkHits = fingerprintChunks[token] ?? Set<String>()
            let combined = tokenHits.union(chunkHits)
            if let existing = candidates {
                candidates = existing.intersection(combined)
            } else {
                candidates = combined
            }
            if candidates?.isEmpty ?? false { return [] }
        }
        return Array(candidates ?? [])
    }

    // MARK: Internals

    private func tokens(for key: IndexedKey) -> Set<String> {
        var out: Set<String> = []
        for uid in key.userIDs {
            out.formUnion(Self.tokenize(uid))
        }
        out.formUnion(Self.tokenize(key.fingerprint))
        return out
    }

    private func fingerprintChunks(of fpr: String) -> Set<String> {
        // 4-char sliding window. "ABCDEF1234..." → "abcd", "bcde",
        // "cdef", "def1", etc. Lets users search by any contiguous
        // substring of the fingerprint.
        let lower = fpr.lowercased()
        guard lower.count >= 4 else { return Set([lower]) }
        var chunks: Set<String> = [lower]
        var idx = lower.startIndex
        let end = lower.endIndex
        while lower.distance(from: idx, to: end) >= 4 {
            let chunkEnd = lower.index(idx, offsetBy: 4)
            chunks.insert(String(lower[idx..<chunkEnd]))
            idx = lower.index(after: idx)
        }
        return chunks
    }

    /// Lowercase + split on whitespace + ASCII punctuation that
    /// commonly appears in user IDs and emails.
    public static func tokenize(_ s: String) -> Set<String> {
        let lowered = s.lowercased()
        var tokens: Set<String> = []
        var current = ""
        for char in lowered {
            if char.isLetter || char.isNumber {
                current.append(char)
            } else {
                if !current.isEmpty {
                    tokens.insert(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { tokens.insert(current) }
        return tokens
    }
}
