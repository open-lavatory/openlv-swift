/// Identity shared with the remote peer during the handshake.
public struct PeerInfo: Sendable, Equatable, Codable {
    public var identity: String
    public var name: String
    public var icon: String?

    public init(identity: String, name: String, icon: String? = nil) {
        self.identity = identity
        self.name = name
        self.icon = icon
    }
}

public enum OpenLVProtocol: String, Sendable, Codable {
    case ntfy
    case mqtt
    case nostr
}

public enum SessionStatus: String, Sendable, Codable {
    case created, signaling, ready, linking, connected, disconnected
}

public enum SignalState: String, Sendable, Codable {
    case standby, connecting, ready, handshake
    case handshakePartial = "handshake_partial"
    case encrypted, error
}

public struct SessionState: Sendable, Equatable, Codable {
    public let status: SessionStatus
    public let signaling: SignalState?
    public let peer: PeerInfo?
    public let error: String?
}

/// Parsed connection parameters. The handshake key is secret; avoid logging it.
public struct SessionURIInfo: Sendable, Equatable, Codable {
    public let sessionID: String
    public let keyHash: String
    public let handshakeKey: String
    public let `protocol`: String
    public let server: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case keyHash = "key_hash"
        case handshakeKey = "handshake_key"
        case `protocol`, server
    }
}

/// Options passed directly to the shared Rust session implementation.
public struct DappOptions: Sendable, Encodable {
    public var sessionID: String?
    public var `protocol`: OpenLVProtocol
    public var server: String
    public var handshakeKey: String?
    public var info: PeerInfo?

    public init(
        sessionID: String? = nil,
        protocol: OpenLVProtocol,
        server: String,
        handshakeKey: String? = nil,
        info: PeerInfo? = nil
    ) {
        self.sessionID = sessionID
        self.protocol = `protocol`
        self.server = server
        self.handshakeKey = handshakeKey
        self.info = info
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case `protocol`, server
        case handshakeKey = "handshake_key"
        case info = "peer_info"
    }
}

/// Response timeout starts when the remote peer acknowledges the request.
public struct RequestTimeouts: Sendable, Equatable {
    public var acknowledgement: Duration
    public var response: Duration

    public init(acknowledgement: Duration = .seconds(10), response: Duration = .seconds(3_600)) {
        self.acknowledgement = acknowledgement
        self.response = response
    }

    public static let `default` = RequestTimeouts()

    static func milliseconds(_ duration: Duration) throws -> UInt64 {
        let parts = duration.components
        guard parts.seconds >= 0, parts.attoseconds >= 0 else {
            throw OpenLVError(kind: .invalidRequestTimeout, message: "Timeout must be positive.")
        }
        let (seconds, overflow) = UInt64(parts.seconds).multipliedReportingOverflow(by: 1_000)
        let (result, addedOverflow) = seconds.addingReportingOverflow(UInt64(parts.attoseconds / 1_000_000_000_000_000))
        guard !overflow, !addedOverflow, result > 0 else {
            throw OpenLVError(kind: .invalidRequestTimeout, message: "Timeout must fit in positive milliseconds.")
        }
        return result
    }
}
