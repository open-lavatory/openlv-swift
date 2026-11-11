import Foundation
import OpenLV

@main
struct SessionDemo {
    static func main() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        let session: OpenLVSession
        if arguments.first == "dapp", arguments.count == 3,
           let protocolName = arguments.dropFirst().first,
           let signalingProtocol = OpenLVProtocol(rawValue: protocolName),
           let server = arguments.last {
            session = try await OpenLV.dapp(options: DappOptions(
                protocol: signalingProtocol,
                server: server,
                info: PeerInfo(identity: "com.example.openlv.dapp", name: "Swift dApp")
            ), onRequest: handle)
        } else if arguments.first == "wallet", let uri = arguments.dropFirst().first {
            session = try await OpenLV.wallet(uri,
                info: PeerInfo(identity: "com.example.openlv.wallet", name: "Swift Wallet"),
                onRequest: handle)
        } else {
            print("Usage: swift run openlv-example (dapp <ntfy|mqtt|nostr> <server> | wallet 'openlv://…')")
            return
        }
        do {
            let states = await session.states()
            let observer = Task {
                for try await state in states {
                    print("State: \(state.status.rawValue)")
                    if state.status == .disconnected {
                        try await session.close()
                        return
                    }
                }
            }
            defer { observer.cancel() }
            try await session.connect()
            if session.isHost { print("Pairing URI: \(session.uri)") }
            try await session.waitForLink()
            if session.isHost {
                let response = try await session.send([
                    "jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": [],
                ])
                print("Response: \(response)")
            } else {
                try await observer.value
            }
            try await session.close()
        } catch {
            try? await session.close()
            throw error
        }
    }

    static func handle(_ message: JSONValue) async throws -> JSONValue {
        if message["method"] == "eth_chainId" {
            return ["jsonrpc": "2.0", "id": message["id"] ?? .null, "result": "0x1"]
        }
        return [
            "jsonrpc": "2.0", "id": message["id"] ?? .null,
            "error": ["code": -32601, "message": "Method not found"],
        ]
    }
}
