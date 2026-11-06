import Foundation
import OpenLV

@main
struct SessionDemo {
    static func main() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        let session: OpenLVSession
        if arguments.first == "dapp" {
            session = try await OpenLV.dapp(options: DappOptions(
                info: PeerInfo(identity: "com.example.openlv.dapp", name: "Swift dApp")
            ), onRequest: handle)
        } else if arguments.first == "wallet", let uri = arguments.dropFirst().first {
            session = try await OpenLV.wallet(uri,
                info: PeerInfo(identity: "com.example.openlv.wallet", name: "Swift Wallet"),
                onRequest: handle)
        } else {
            print("Usage: swift run openlv-example dapp | wallet 'openlv://…'")
            return
        }
        do {
            let states = await session.states()
            let observer = Task {
                for try await state in states { print("State: \(state.status.rawValue)") }
            }
            defer { observer.cancel() }
            try await session.connect()
            if session.isHost { print("Pairing URI: \(session.uri)") }
            try await session.waitForLink()
            let response = try await session.send([
                "jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": [],
            ])
            print("Response: \(response)")
            if !session.isHost {
                for try await _ in await session.states() {}
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
