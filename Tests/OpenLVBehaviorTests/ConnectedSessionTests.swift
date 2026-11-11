import Foundation
import Dispatch
import Testing
import OpenLV

// Opt in with a local MQTT broker. Ordinary tests need no network service.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OPENLV_TEST_MQTT_SERVER"] != nil))
func connectedSessionsExchangeRequestsAndMapHandlerFailures() async throws {
    let server = try #require(ProcessInfo.processInfo.environment["OPENLV_TEST_MQTT_SERVER"])
    let hostInfo = PeerInfo(identity: "com.example.host", name: "Test Host", icon: "https://example.com/host.png")
    let walletInfo = PeerInfo(identity: "com.example.wallet", name: "Test Wallet")
    let host = try await OpenLV.dapp(
        options: DappOptions(protocol: .mqtt, server: server, info: hostInfo),
        onRequest: echo
    )
    let wallet = try await OpenLV.wallet(host.uri, info: walletInfo, onRequest: echo)
    // Stock UniFFI calls do not respond to Swift cancellation. Shutdown is the
    // watchdog's escape hatch if signaling or transport never becomes ready.
    let watchdog = DispatchWorkItem {
        Task {
            try? await host.close()
            try? await wallet.close()
        }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: watchdog)
    defer { watchdog.cancel() }
    do {
        try await host.connect()
        try await wallet.connect()
        async let hostLink: Void = host.waitForLink()
        async let walletLink: Void = wallet.waitForLink()
        _ = try await (hostLink, walletLink)

        let hostState = try await host.state()
        let walletState = try await wallet.state()
        #expect(hostState.peer == walletInfo)
        #expect(walletState.peer == hostInfo)

        let message: JSONValue = ["method": "echo", "params": ["value": .unsignedInteger(UInt64.max)]]
        let fromHost = try await host.send(message)
        let fromWallet = try await wallet.send(message)
        #expect(fromHost == message)
        #expect(fromWallet == message)

        do {
            _ = try await host.send(["method": "fail"])
            Issue.record("Expected remote handler failure")
        } catch let error as OpenLVError {
            #expect(error.kind == .requestFailed)
        }
        try await wallet.close()
        try await host.close()
    } catch {
        try? await wallet.close()
        try? await host.close()
        throw error
    }
}

private func echo(_ request: JSONValue) async throws -> JSONValue {
    if request["method"] == "fail" {
        throw OpenLVError(kind: .other, message: "Deliberate handler failure")
    }
    return request
}
