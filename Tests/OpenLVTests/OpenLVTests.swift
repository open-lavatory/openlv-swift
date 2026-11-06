import Foundation
import Testing
@testable import OpenLV

struct OpenLVTests {
    private let info = PeerInfo(identity: "com.example.openlv.swift", name: "Swift test")

    @Test func testSessionIDsAreRandomAndURLSafe() {
        let ids = (0..<100).map { _ in OpenLV.generateSessionID() }
        #expect(Set(ids).count == 100)
        for id in ids {
            #expect(id.count == 16)
            #expect(id.range(of: "^[A-Za-z0-9_-]{16}$", options: .regularExpression) != nil)
        }
    }

    @Test func testKnownURIAndInvalidURI() throws {
        let parsed = try OpenLV.parseURI(
            "openlv://k7n8m9x2w5q1p3r6@1?h=a1b2c3d4e5f60708"
            + "&k=0123456789abcdef0123456789abcdef&p=mqtt"
            + "&s=wss%3A%2F%2Ftest.mosquitto.org%3A8081%2Fmqtt"
        )
        #expect(parsed.sessionID == "k7n8m9x2w5q1p3r6")
        #expect(parsed.keyHash == "a1b2c3d4e5f60708")
        #expect(parsed.handshakeKey == "0123456789abcdef0123456789abcdef")
        #expect(parsed.protocol == "mqtt")
        #expect(parsed.server == "wss://test.mosquitto.org:8081/mqtt")
        do {
            _ = try OpenLV.parseURI("not-a-uri")
            Issue.record("Expected invalid URI")
        } catch { #expect((error as? OpenLVError)?.kind == .invalidURI) }
    }

    @Test func testDappWalletAndOptionsRoundTrip() async throws {
        let dapp = try await OpenLV.dapp(options: DappOptions(
            sessionID: "k7n8m9x2w5q1p3r6", protocol: .mqtt,
            server: "wss://test.mosquitto.org:8081/mqtt",
            handshakeKey: "0123456789abcdef0123456789abcdef", info: info
        )) { $0 }
        let parsed = try OpenLV.parseURI(dapp.uri)
        #expect(dapp.isHost)
        #expect(dapp.sessionID == parsed.sessionID)
        #expect(parsed.handshakeKey == "0123456789abcdef0123456789abcdef")
        #expect(parsed.protocol == "mqtt")
        #expect(parsed.server == "wss://test.mosquitto.org:8081/mqtt")
        let state = try await dapp.state()
        #expect(state.status == .created)
        let wallet = try await OpenLV.wallet(dapp.uri, info: info) { $0 }
        #expect(!(wallet.isHost))
        #expect(wallet.sessionID == dapp.sessionID)
        try await wallet.close()
        try await dapp.close()
    }

    @Test func testNativeValidationErrorsAreTyped() async throws {
        do {
            _ = try await OpenLV.wallet("not-a-uri") { $0 }
            Issue.record("Expected invalid URI")
        } catch { #expect((error as? OpenLVError)?.kind == .invalidURI) }
        do {
            _ = try await OpenLV.dapp(options: DappOptions(handshakeKey: "not-hex")) { $0 }
            Issue.record("Expected encryption failure")
        } catch { #expect((error as? OpenLVError)?.kind == .encryption) }
        do {
            _ = try await OpenLV.dapp(options: DappOptions(info: PeerInfo(identity: "", name: "Test"))) { $0 }
            Issue.record("Expected invalid identity")
        } catch { #expect((error as? OpenLVError)?.kind == .session) }
    }

    @Test func testSendBeforeConnectAndAfterClose() async throws {
        let session = try await OpenLV.dapp { $0 }
        do {
            _ = try await session.send(["method": "eth_chainId", "params": []])
            Issue.record("Expected unconnected session error")
        } catch { #expect((error as? OpenLVError)?.kind == .session) }
        try await session.close()
        do {
            _ = try await session.send("closed")
            Issue.record("Expected closed session error")
        } catch { #expect((error as? OpenLVError)?.kind == .sessionClosed) }
        do {
            try await session.connect()
            Issue.record("Expected closed session error")
        } catch { #expect((error as? OpenLVError)?.kind == .sessionClosed) }
    }

    @Test func testConcurrentCloseUnblocksWaitersAndAllSubscribers() async throws {
        let session = try await OpenLV.dapp { $0 }
        let first = await session.states()
        let second = await session.states()
        let firstConsumer = Task { for try await _ in first {} }
        let secondConsumer = Task { for try await _ in second {} }
        let waiter = Task {
            do {
                try await session.waitForLink()
                Issue.record("Expected closed session error")
            } catch { #expect((error as? OpenLVError)?.kind == .sessionClosed) }
        }
        async let closeOne: Void = session.close()
        async let closeTwo: Void = session.close()
        _ = try await (closeOne, closeTwo)
        await waiter.value
        try await firstConsumer.value
        try await secondConsumer.value
        let state = try await session.state()
        #expect(state.status == .disconnected)
    }

    @Test func testCancellationOfLinkWait() async throws {
        let session = try await OpenLV.dapp { $0 }
        let waiter = Task { try await session.waitForLink() }
        try await Task.sleep(for: .milliseconds(30))
        waiter.cancel()
        do {
            try await waiter.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError, "Unexpected error: \(error)") }
        try await session.close()
    }

    @Test func testCancellingSubscriptionDoesNotCloseSession() async throws {
        let session = try await OpenLV.dapp { $0 }
        let states = await session.states()
        let consumer = Task { for try await _ in states {} }
        try await Task.sleep(for: .milliseconds(30))
        consumer.cancel()
        do { try await consumer.value }
        catch { #expect(error is CancellationError) }
        let state = try await session.state()
        #expect(state.status == .created)
        try await session.close()
    }

    @Test func testCancellationRacesNativeCompletion() async throws {
        let session = try await OpenLV.dapp { $0 }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    let operation = Task { try await session.send(.integer(Int64(index))) }
                    if index.isMultiple(of: 2) { await Task.yield() }
                    operation.cancel()
                    do {
                        _ = try await operation.value
                        Issue.record("Unconnected session unexpectedly sent a message")
                    } catch {
                        #expect(error is CancellationError || (error as? OpenLVError)?.kind == .session)
                    }
                }
            }
        }
        try await session.close()
    }

    @Test func testDropInitiatesShutdownWithoutRetainCycle() async throws {
        var session: OpenLVSession? = try await OpenLV.dapp { $0 }
        weak var reference = session
        let stream = await session!.states()
        session = nil
        #expect(reference == nil)
        reference = nil
        for try await _ in stream {}
    }

    @Test func testJSONPreservesScalarsContainersAndLargeIntegers() throws {
        let value: JSONValue = [
            "null": nil, "boolean": true, "integer": 9_007_199_254_740_993,
            "text": "héllo 🌍", "list": [1, 2, 3], "fraction": 1.5,
        ]
        #expect(try JSON.decode(JSONValue.self, from: JSON.encode(value)) == value)
        let maximum = JSONValue.unsignedInteger(UInt64.max)
        #expect(try JSON.decode(JSONValue.self, from: JSON.encode(maximum)) == maximum)
        #expect(throws: (any Error).self) { try JSON.encode(JSONValue.number(.nan)) }
        struct Message: Codable, Equatable { let method: String; let params: [Int] }
        let model = Message(method: "test", params: [1, 2])
        #expect(try JSONValue(encoding: model).decode(Message.self) == model)
    }

    @Test func testTimeoutConversionRejectsInvalidAndOverflowingValues() throws {
        #expect(try RequestTimeouts.milliseconds(.seconds(10)) == 10_000)
        #expect(try RequestTimeouts.milliseconds(.milliseconds(1)) == 1)
        #expect(throws: (any Error).self) { try RequestTimeouts.milliseconds(.zero) }
        #expect(throws: (any Error).self) { try RequestTimeouts.milliseconds(.nanoseconds(1)) }
        #expect(throws: (any Error).self) { try RequestTimeouts.milliseconds(.seconds(-1)) }
        #expect(throws: (any Error).self) { try RequestTimeouts.milliseconds(.seconds(Int64.max)) }
    }
}
