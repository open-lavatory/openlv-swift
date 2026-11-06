import OpenLVNative

/// A handler returns the complete JSON response, including JSON-RPC id/result/error
/// when using JSON-RPC. Handlers run concurrently. Throwing fails the remote request.
public typealias RequestHandler = @Sendable (JSONValue) async throws -> JSONValue

public enum OpenLV {
    /// Create a host session. Call `connect()` to start signaling.
    public static func dapp(
        options: DappOptions = DappOptions(),
        onRequest: @escaping RequestHandler
    ) async throws -> OpenLVSession {
        try await guarded {
            let native = try await OpenLVNative.createDapp(optionsJson: JSON.encode(options))
            return await OpenLVSession.make(native: native, handler: onRequest)
        }
    }

    /// Create a wallet from the host's connection URI, then call `connect()`.
    public static func wallet(
        _ uri: String,
        info: PeerInfo? = nil,
        onRequest: @escaping RequestHandler
    ) async throws -> OpenLVSession {
        try await guarded {
            let native = try await OpenLVNative.createWallet(uri: uri, peerInfoJson: JSON.encode(info))
            return await OpenLVSession.make(native: native, handler: onRequest)
        }
    }

    public static func parseURI(_ uri: String) throws -> SessionURIInfo {
        do {
            return try JSON.decode(SessionURIInfo.self, from: OpenLVNative.parseSessionUri(url: uri))
        } catch { throw mappedError(error) }
    }

    /// Generate a random, URL-safe, 16-character session identifier in Rust.
    public static func generateSessionID() -> String {
        OpenLVNative.generateSessionId()
    }
}
