import Foundation
import OpenLVNative

public enum OpenLVErrorKind: String, Sendable, Codable {
    case invalidURI = "invalid_uri"
    case signaling, transport, session
    case sessionClosed = "session_closed"
    case requestLimitReached = "request_limit_reached"
    case requestFailed = "request_failed"
    case invalidRequestTimeout = "invalid_request_timeout"
    case responseChannelClosed = "response_channel_closed"
    case encryption
    case wireFrame = "wire_frame"
    case protocolViolation = "protocol_violation"
    case unsupportedProtocol = "unsupported_protocol"
    case noConnection = "no_connection"
    case requestTimeout = "request_timeout"
    case other
}

public struct OpenLVError: Error, Sendable, Equatable, LocalizedError {
    public let kind: OpenLVErrorKind
    /// Retains the native category even if a future Rust release adds a new one.
    public let nativeKind: String
    public let message: String
    public var errorDescription: String? { message }

    public init(kind: OpenLVErrorKind, message: String) {
        self.kind = kind
        self.nativeKind = kind.rawValue
        self.message = message
    }

    init(nativeKind: String, message: String) {
        self.kind = OpenLVErrorKind(rawValue: nativeKind) ?? .other
        self.nativeKind = nativeKind
        self.message = message
    }
}

func mappedError(_ error: any Error) -> any Error {
    if error is CancellationError { return error }
    if let error = error as? OpenLVError { return error }
    if case let BridgeError.Failure(kind, message) = error {
        return OpenLVError(nativeKind: kind, message: message)
    }
    return OpenLVError(kind: .other, message: String(describing: error))
}

func guarded<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ operation: () async throws -> T
) async throws -> T {
    do { return try await operation() }
    catch { throw mappedError(error) }
}
