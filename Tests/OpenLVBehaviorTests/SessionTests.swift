import Testing
import OpenLV

@Test(arguments: [OpenLVProtocol.ntfy, .mqtt, .nostr])
func createsHostAndWalletFromExplicitServer(protocol signalingProtocol: OpenLVProtocol) async throws {
    let server: String
    switch signalingProtocol {
    case .ntfy: server = "http://127.0.0.1:19876/"
    case .mqtt, .nostr: server = "ws://127.0.0.1:19876/"
    }
    let host = try await OpenLV.dapp(options: DappOptions(protocol: signalingProtocol, server: server)) { $0 }
    let parsed = try OpenLV.parseURI(host.uri)
    let hostState = try await host.state()
    let wallet = try await OpenLV.wallet(host.uri) { $0 }
    let walletState = try await wallet.state()
    try await wallet.close()
    try await host.close()

    #expect(host.isHost)
    #expect(!wallet.isHost)
    #expect(parsed.sessionID == host.sessionID)
    #expect(wallet.sessionID == host.sessionID)
    #expect(parsed.server == server)
    #expect(parsed.protocol == signalingProtocol.rawValue)
    #expect(hostState.status == .created)
    #expect(walletState.status == .created)
}

@Test func closingFinishesSubscriptionsAndCanBeRepeated() async throws {
    let session = try await OpenLV.dapp(options: DappOptions(protocol: .ntfy, server: "http://127.0.0.1:19876/")) { $0 }
    let states = await session.states()
    let observer = Task {
        for try await _ in states {}
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            group.addTask { try await session.close() }
        }
        try await group.waitForAll()
    }
    try await observer.value
    try await session.close()
    var lateObserver = await session.states().makeAsyncIterator()
    let nextState = try await lateObserver.next()
    #expect(nextState == nil)

    await expectFailure(.sessionClosed) { try await session.connect() }
    await expectFailure(.sessionClosed) { try await session.waitForLink() }
    await expectFailure(.sessionClosed) { _ = try await session.send(.null) }
}

@Test func mapsInvalidWalletURIToPublicError() async {
    await expectFailure(.invalidURI) {
        _ = try await OpenLV.wallet("invalid") { $0 }
    }
}

@Test func rejectsInvalidTimeoutsBeforeSending() async throws {
    let session = try await OpenLV.dapp(options: DappOptions(protocol: .ntfy, server: "http://127.0.0.1:19876/")) { $0 }
    for invalid: Duration in [.zero, .nanoseconds(1), .seconds(-1), .seconds(Int64.max)] {
        await expectFailure(.invalidRequestTimeout) {
            _ = try await session.send(.null, timeouts: RequestTimeouts(acknowledgement: invalid))
        }
        await expectFailure(.invalidRequestTimeout) {
            _ = try await session.send(.null, timeouts: RequestTimeouts(response: invalid))
        }
    }
    try await session.close()
}

@Test func droppingSessionFinishesItsStateStream() async throws {
    let states = try await makeStreamWithoutKeepingSession()
    for try await _ in states {}
}

private func makeStreamWithoutKeepingSession() async throws -> AsyncThrowingStream<SessionState, any Error> {
    let session = try await OpenLV.dapp(options: DappOptions(protocol: .ntfy, server: "http://127.0.0.1:19876/")) { $0 }
    return await session.states()
}

@Test func closingReleasesLinkWaitersAndCancelledObservers() async throws {
    let session = try await OpenLV.dapp(options: DappOptions(protocol: .ntfy, server: "http://127.0.0.1:19876/")) { $0 }
    let states = await session.states()
    let observer = Task { for try await _ in states {} }
    let link = Task { await expectFailure(.sessionClosed) { try await session.waitForLink() } }
    observer.cancel()
    try await session.close()
    try await observer.value
    await link.value
}

@Test func preservesExplicitSessionParameters() async throws {
    // Public fixture data, not a production handshake key.
    let handshakeKey = String(repeating: "ab", count: 16)
    let session = try await OpenLV.dapp(options: DappOptions(
        sessionID: "swift_test_00001",
        protocol: .ntfy,
        server: "http://127.0.0.1:19876/",
        handshakeKey: handshakeKey,
        info: PeerInfo(identity: "com.example.swift", name: "Swift Test", icon: "https://example.com/icon.png")
    )) { $0 }
    let parsed = try OpenLV.parseURI(session.uri)
    try await session.close()
    #expect(parsed.sessionID == "swift_test_00001")
    #expect(parsed.handshakeKey == handshakeKey)
}

@Test func rejectsInvalidPeerMetadata() async {
    await expectFailure(.session) {
        _ = try await OpenLV.dapp(options: DappOptions(
            protocol: .ntfy, server: "http://127.0.0.1:19876/",
            info: PeerInfo(identity: "", name: "Invalid peer")
        )) { $0 }
    }
}

private func expectFailure(
    _ kind: OpenLVErrorKind,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected OpenLVError with kind \(kind)")
    } catch let error as OpenLVError {
        #expect(error.kind == kind)
    } catch {
        Issue.record("Expected OpenLVError, got \(type(of: error))")
    }
}
