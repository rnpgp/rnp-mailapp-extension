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

    /// Looks up a key by fingerprint on VKS.
    public func discoverByFingerprint(_ fingerprint: String) async -> Result<FetchedKey, KeyServerError> {
        do {
            let data = try await client.fetchByFingerprint(fingerprint)
            return .success(FetchedKey(data: data, source: "keys.openpgp.org"))
        } catch {
            return .failure(error as? KeyServerError ?? .network(underlying: error.localizedDescription))
        }
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
