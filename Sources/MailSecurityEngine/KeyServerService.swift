//
//  KeyServerService.swift
//  swift-rnp
//
//  High-level keyserver publish/discovery operations backed by
//  KeyServerClient.
//

@_exported import KeyServerClient
import Foundation

/// Result of fetching a key from a keyserver.
public struct FetchedKey: Equatable {
    /// Raw key data (armored or binary).
    public let data: Data
    /// Human-readable source description.
    public let source: String

    public init(data: Data, source: String) {
        self.data = data
        self.source = source
    }
}

/// High-level service for publishing and discovering keys.
public final class KeyServerService: Sendable {
    private let client: KeyServerClient

    public init(client: KeyServerClient = URLSessionKeyServerClient()) {
        self.client = client
    }

    /// Uploads an armored public key to the default keyserver.
    public func upload(armoredKey: String) async throws -> UploadReceipt {
        try await client.upload(armoredKey: armoredKey)
    }

    /// Looks up a key by email, trying WKD first, then VKS by-email.
    public func discoverByEmail(_ email: String) async -> Result<FetchedKey, KeyServerError> {
        // Try WKD advanced method first, then direct method, then VKS.
        if case let .success(data) = await fetchWKD(email: email, advanced: true) {
            return .success(FetchedKey(data: data, source: "WKD (advanced)"))
        }
        if case let .success(data) = await fetchWKD(email: email, advanced: false) {
            return .success(FetchedKey(data: data, source: "WKD (direct)"))
        }
        do {
            let data = try await client.fetchByEmail(email)
            return .success(FetchedKey(data: data, source: "keys.openpgp.org"))
        } catch {
            return .failure(error as? KeyServerError ?? .network(underlying: error.localizedDescription))
        }
    }

    /// Looks up a key by fingerprint, trying VKS first, then HKP keyservers.
    ///
    /// VKS (keys.openpgp.org) only serves keys with verified user IDs, so a
    /// key that was never uploaded there — or whose email was never verified —
    /// is missed. HKP keyservers carry unverified uploads too and are tried
    /// next, in `HKPSServer.allCases` order.
    public func discoverByFingerprint(_ fingerprint: String) async -> Result<FetchedKey, KeyServerError> {
        do {
            let data = try await client.fetchByFingerprint(fingerprint)
            return .success(FetchedKey(data: data, source: "keys.openpgp.org"))
        } catch {
            // Fall through to HKP below.
        }
        var lastError: KeyServerError = .notFound
        for server in HKPSServer.allCases {
            do {
                let data = try await client.fetchHKPS(fingerprint: fingerprint, server: server)
                return .success(FetchedKey(data: data, source: "\(server.rawValue) (HKPS)"))
            } catch {
                lastError = error as? KeyServerError ?? .network(underlying: error.localizedDescription)
            }
        }
        return .failure(lastError)
    }

    /// Looks up a key by fingerprint, falling back to email discovery.
    ///
    /// Fingerprint lookup is tried first when a fingerprint is available —
    /// it identifies the exact key, unlike an email search, which can return
    /// any key carrying the address. When the fingerprint is unavailable or
    /// not found on any server, the email path (`discoverByEmail`: WKD, then
    /// VKS) is tried. Returns `.notFound` when neither identifier is given.
    public func discover(fingerprint: String?, email: String?) async -> Result<FetchedKey, KeyServerError> {
        var lastError: KeyServerError = .notFound
        if let fingerprint, !fingerprint.isEmpty {
            switch await discoverByFingerprint(fingerprint) {
            case let .success(key):
                return .success(key)
            case let .failure(error):
                lastError = error
            }
        }
        if let email, !email.isEmpty {
            switch await discoverByEmail(email) {
            case let .success(key):
                return .success(key)
            case let .failure(error):
                lastError = error
            }
        }
        return .failure(lastError)
    }

    private func fetchWKD(email: String, advanced: Bool) async -> Result<Data, Error> {
        do {
            let data = try await client.fetchWKD(email: email, advanced: advanced)
            return .success(data)
        } catch {
            return .failure(error)
        }
    }
}
