#!/bin/bash
# Compile, link, and run the public API from an independent macOS Swift package.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
consumer="$(mktemp -d "${TMPDIR:-/tmp}/openlv-consumer.XXXXXX")"
trap 'rm -rf "$consumer"' EXIT
mkdir -p "$consumer/Sources/Consumer"
python3 - "$root" "$consumer/Package.swift" <<'PY'
import json
from pathlib import Path
import sys

# JSON string escaping also protects the Swift literal for normal filesystem paths.
path = json.dumps(sys.argv[1], ensure_ascii=False)
Path(sys.argv[2]).write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "OpenLV", path: PATH_LITERAL)],
    targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "OpenLV", package: "OpenLV")])]
)
'''.replace('PATH_LITERAL', path))
PY
cat > "$consumer/Sources/Consumer/main.swift" <<'SWIFT'
import OpenLV

@main struct Consumer {
    static func main() async throws {
        let session = try await OpenLV.dapp { $0 }
        do {
            let parsed = try OpenLV.parseURI(session.uri)
            precondition(parsed.sessionID == session.sessionID)
            let state = try await session.state()
            precondition(state.status == .created)
            let value: JSONValue = ["id": 9_007_199_254_740_993, "params": [true, nil]]
            let decoded = try value.decode(JSONValue.self)
            precondition(decoded == value)
            try await session.close()
            let closed = try await session.state()
            precondition(closed.status == .disconnected)
        } catch {
            try? await session.close()
            throw error
        }
        print("OpenLV external consumer passed")
    }
}
SWIFT
swift run --package-path "$consumer" -c release Consumer
