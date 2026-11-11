import Foundation
import OpenLVNative

/// A session backed by Rust's signaling, encryption, and WebRTC implementation.
/// Call `close()` when finished. Dropping this object also initiates shutdown.
public actor OpenLVSession {
    public nonisolated let uri: String
    public nonisolated let sessionID: String
    public nonisolated let isHost: Bool

    private let native: OpenLVNative.Session
    private let requestTask: Task<Void, Never>
    private var closeTask: Task<Void, any Error>?

    private init(
        native: OpenLVNative.Session, uri: String, sessionID: String,
        handler: @escaping RequestHandler
    ) {
        self.native = native
        self.uri = uri
        self.sessionID = sessionID
        self.isHost = native.isHost()
        // Capture the native object, not self, so the pump cannot retain the wrapper.
        self.requestTask = Task.detached {
            await Self.serveRequests(native: native, handler: handler)
        }
    }

    static func make(native: OpenLVNative.Session, handler: @escaping RequestHandler) async -> OpenLVSession {
        let uri = await native.uri()
        let id = await native.sessionId()
        return OpenLVSession(native: native, uri: uri, sessionID: id, handler: handler)
    }

    deinit {
        requestTask.cancel()
        if closeTask == nil {
            let session = native
            Task { try? await session.shutdown() }
        }
    }

    public func connect() async throws {
        try checkOpen()
        try await guarded { try await native.connect() }
    }

    public func waitForLink() async throws {
        try checkOpen()
        try await guarded { try await native.waitForLink() }
    }

    public func state() async throws -> SessionState {
        try await guarded {
            try JSON.decode(SessionState.self, from: await native.state())
        }
    }

    /// Each call subscribes independently to future changes. Use `state()` for a
    /// snapshot. The stream ends on shutdown; slow consumers may miss updates.
    /// Consume each returned stream with one task.
    /// UniFFI does not propagate Swift task cancellation to a pending native
    /// wait. Call `close()` to release waiting observers before awaiting them.
    public func states() -> AsyncThrowingStream<SessionState, any Error> {
        let subscription = native.subscribeStates()
        return AsyncThrowingStream(unfolding: {
            try await guarded {
                guard let value = try await subscription.nextState() else { return nil }
                return try JSON.decode(SessionState.self, from: value)
            }
        })
    }

    public func send(
        _ message: JSONValue,
        timeouts: RequestTimeouts = .default
    ) async throws -> JSONValue {
        try checkOpen()
        return try await guarded {
            let ack = try RequestTimeouts.milliseconds(timeouts.acknowledgement)
            let response = try RequestTimeouts.milliseconds(timeouts.response)
            let result = try await native.sendWithTimeouts(
                message: JSON.encode(message), ackTimeoutMs: ack, responseTimeoutMs: response
            )
            return try JSON.decode(JSONValue.self, from: result)
        }
    }

    /// Concurrent calls share one shutdown task. Closing cancels native pending
    /// operations and finishes subscriptions, without waiting for user handlers.
    /// A handler may finish later; Rust discards replies to cancelled requests.
    public func close() async throws {
        if let closeTask { return try await closeTask.value }
        let session = native
        let pump = requestTask
        let task = Task<Void, any Error> {
            defer { pump.cancel() }
            try await guarded { try await session.shutdown() }
            await pump.value
        }
        closeTask = task
        try await task.value
    }

    private func checkOpen() throws {
        if closeTask != nil {
            throw OpenLVError(kind: .sessionClosed, message: "Session is closed.")
        }
    }

    private struct Request: Decodable {
        let id: UInt64
        let message: String
    }

    private static func serveRequests(native: OpenLVNative.Session, handler: @escaping RequestHandler) async {
        do {
            while !Task.isCancelled, let source = try await native.nextRequest() {
                let request = try JSON.decode(Request.self, from: source)
                Task.detached {
                    do {
                        let message = try JSON.decode(JSONValue.self, from: request.message)
                        let response = try JSON.encode(await handler(message))
                        try native.respond(id: request.id, response: response)
                    } catch {
                        // A closed session or a remote timeout can make this reply stale.
                        try? native.fail(id: request.id)
                    }
                }
            }
        } catch {
            // Stop pending remote calls if the request pump cannot continue.
            try? await native.shutdown()
        }
    }
}
