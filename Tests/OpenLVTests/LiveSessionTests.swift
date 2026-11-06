import Foundation
import Testing
import OpenLV

/// Opt in with OPENLV_LIVE_TESTS=1. Uses real signaling and WebRTC.
struct LiveSessionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENLV_LIVE_TESTS"] == "1"))
    func testBidirectionalRequestsConcurrencyFailuresTimeoutsAndClose() async throws {
        let mqtt = ProcessInfo.processInfo.environment["OPENLV_TEST_MQTT_SERVER"]
        let activity = Activity()
        let held = AsyncStream<Void>.makeStream()
        let dapp = try await OpenLV.dapp(options: DappOptions(
            protocol: mqtt == nil ? .ntfy : .mqtt,
            server: mqtt,
            info: PeerInfo(identity: "com.example.swift.dapp", name: "Swift dApp")
        )) { message in
            ["echo": message]
        }
        let wallet = try await OpenLV.wallet(
            dapp.uri, info: PeerInfo(identity: "com.example.swift.wallet", name: "Swift Wallet")
        ) { message in
            if message["method"] == "fail" {
                throw OpenLVError(kind: .other, message: "Test handler failure")
            }
            if message["method"] == "nan" { return .number(.nan) }
            if message["method"] == "hold" {
                held.continuation.yield(())
                try await Task.sleep(for: .seconds(2))
            }
            await activity.enter()
            try await Task.sleep(for: .milliseconds(100))
            await activity.leave()
            return ["echo": message]
        }

        do {
            try await within(.seconds(60)) {
                try await dapp.connect()
                try await wallet.connect()
                async let host: Void = dapp.waitForLink()
                async let client: Void = wallet.waitForLink()
                _ = try await (host, client)
            }
            let hostState = try await dapp.state()
            let walletState = try await wallet.state()
            #expect(hostState.peer?.identity == "com.example.swift.wallet")
            #expect(walletState.peer?.identity == "com.example.swift.dapp")

            let payload: JSONValue = ["id": 9_007_199_254_740_993, "params": [true, nil, "hello"]]
            let reply = try await wallet.send(payload)
            #expect(reply == ["echo": payload])
            let replies = try await within(.seconds(15)) {
                try await withThrowingTaskGroup(of: JSONValue.self) { group in
                    for id in 0..<8 {
                        group.addTask { try await dapp.send(.integer(Int64(id))) }
                    }
                    var values: [JSONValue] = []
                    for try await value in group { values.append(value) }
                    return values
                }
            }
            #expect(replies.count == 8)
            for id in 0..<8 { #expect(replies.contains(["echo": .integer(Int64(id))])) }
            let maximum = await activity.maximum
            #expect(maximum > 1)

            do {
                _ = try await dapp.send(["method": "fail"])
                Issue.record("Expected remote handler failure")
            } catch { #expect((error as? OpenLVError)?.kind == .requestFailed) }

            do {
                _ = try await dapp.send(["method": "nan"])
                Issue.record("Expected response encoding failure")
            } catch { #expect((error as? OpenLVError)?.kind == .requestFailed) }

            do {
                _ = try await dapp.send("slow", timeouts: RequestTimeouts(response: .milliseconds(20)))
                Issue.record("Expected response timeout")
            } catch { #expect((error as? OpenLVError)?.kind == .requestTimeout) }

            let pending = Task { try await dapp.send(["method": "hold"]) }
            try await within(.seconds(10)) {
                var iterator = held.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
            try await within(.seconds(2)) { try await dapp.close() }
            do {
                _ = try await pending.value
                Issue.record("Expected close to cancel the send")
            } catch { #expect((error as? OpenLVError)?.kind == .sessionClosed) }
            try await wallet.close()
        } catch {
            try? await dapp.close()
            try? await wallet.close()
            throw error
        }
    }
}

private actor Activity {
    private var current = 0
    private(set) var maximum = 0
    func enter() { current += 1; maximum = max(maximum, current) }
    func leave() { current -= 1 }
}

private func within<T: Sendable>(
    _ timeout: Duration, operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: timeout)
            throw OpenLVError(kind: .other, message: "Live test deadline exceeded")
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
