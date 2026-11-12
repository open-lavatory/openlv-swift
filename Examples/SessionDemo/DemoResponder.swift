import Foundation
import OpenLV
import CryptoSwift
import P256K

enum DemoResponder {
    static func account() throws -> String {
        let publicKey = try signingKey().publicKey.dataRepresentation
        let hash = CryptoSwift.SHA3(variant: .keccak256).calculate(for: Array(publicKey.dropFirst()))
        return hex(Array(hash.suffix(20)))
    }

    private static func signingKey() throws -> P256K.Recovery.PrivateKey {
        try P256K.Recovery.PrivateKey(
            dataRepresentation: [UInt8](repeating: 0, count: 31) + [1],
            format: .uncompressed
        )
    }

    static func respond(to request: JSONValue) async throws -> JSONValue {
        let result: JSONValue
        switch request["method"]?.stringValue {
        case "eth_chainId": result = "0x1"
        case "eth_accounts", "eth_requestAccounts": result = [.string(try account())]
        case "personal_sign": return try personalSign(request)
        default:
            return [
                "jsonrpc": "2.0",
                "id": request["id"] ?? .null,
                "error": [
                    "code": -32601,
                    "message": .string("Method not found: \(request["method"]?.stringValue ?? "<missing>") (demo wallet does not send transactions)"),
                ],
            ]
        }
        return ["jsonrpc": "2.0", "id": request["id"] ?? .null, "result": result]
    }

    private static func personalSign(_ request: JSONValue) throws -> JSONValue {
        guard case .array(let params) = request["params"], params.count == 2,
              case .string(let message) = params[0],
              case .string(let address) = params[1],
              let bytes = decodeHex(message) else {
            return failure(request, code: -32602, message: "Expected [hex-encoded message, account]")
        }
        guard address.lowercased() == (try account()) else {
            return failure(request, code: 4100, message: "Requested account is not available")
        }
        let prefix = Array("\u{19}Ethereum Signed Message:\n\(bytes.count)".utf8)
        let hash = CryptoSwift.SHA3(variant: .keccak256).calculate(for: prefix + bytes)
        let signature = try signingKey().signature(for: HashDigest(hash))
        let compact = try signature.compactRepresentation
        guard (0...1).contains(compact.recoveryId),
              let recovery = UInt8(exactly: compact.recoveryId + 27) else {
            return failure(request, code: -32603, message: "Could not encode signature")
        }
        return [
            "jsonrpc": "2.0", "id": request["id"] ?? .null,
            "result": .string(hex(Array(compact.signature) + [recovery])),
        ]
    }

    private static func decodeHex(_ value: String) -> [UInt8]? {
        guard value.hasPrefix("0x") else { return nil }
        var digits = value.dropFirst(2).makeIterator()
        var bytes: [UInt8] = []
        while let first = digits.next() {
            guard let second = digits.next(),
                  first.isHexDigit, second.isHexDigit,
                  let byte = UInt8(String([first, second]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func failure(_ request: JSONValue, code: Int64, message: String) -> JSONValue {
        [
            "jsonrpc": "2.0", "id": request["id"] ?? .null,
            "error": ["code": .integer(code), "message": .string(message)],
        ]
    }
}
