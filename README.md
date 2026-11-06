# OpenLV for Swift

Swift bindings for [Open Lavatory](https://openlv.sh), a peer-to-peer connectivity
protocol for dApps and wallets. The library uses the shared
[`openlv-ffi`](https://github.com/open-lavatory/openlv-rs/tree/master/crates/openlv-ffi)
Rust bridge through generated UniFFI bindings. Rust handles signaling, encryption,
and WebRTC; Swift provides typed models, async request handlers, and state streams.
The API follows the [Dart package](https://github.com/open-lavatory/openlv-dart).

Requires Swift 6, macOS 13+ or iOS 16+. Native builds require Rust 1.91+ and
Python 3. Full Xcode is required for iOS and universal Apple builds.

## Build and use

This initial source package builds its native dependency locally. From this directory:

```sh
# For macOS development on the current machine (Command Line Tools are enough):
./scripts/build-native.sh --host
./scripts/test.sh

# For iOS devices, iOS Simulator, and universal macOS:
./scripts/build-native.sh --all
```

Build the XCFramework **before** opening `Package.swift` in Xcode or adding this
directory as a local package dependency. Add the `OpenLV` product to your app.
The host build replaces the XCFramework with a single macOS slice; rerun `--all`
before building an iOS app.

`Native/OpenLVFFI.xcframework` is generated and ignored by Git. A fresh checkout
needs the build step above. Remote SwiftPM distribution will require publishing
the complete XCFramework and changing the binary target to a release URL and
SwiftPM checksum. No prebuilt release is published by this repository yet.

The Rust dependency and generator are pinned to `openlv-ffi = 0.1.0` and
`uniffi = 0.32.2`; `rust/Cargo.lock` pins transitive dependencies. The build script
regenerates `Sources/OpenLVNative/OpenLVNative.swift` from that exact native library.
Commit generated Swift changes together with dependency updates; keep UniFFI's
generated ABI checks enabled. `scripts/patch-swift-cancellation.py` adds cancellation
to throwing async APIs because UniFFI 0.32.2 does not generate it for Swift. The patch
uses UniFFI's exported future-cancel functions, synchronizes cancellation with handle
disposal, and stops with an error if the expected generator template changes.

## dApp

```swift
import OpenLV

let dapp = try await OpenLV.dapp(options: DappOptions(
    info: PeerInfo(identity: "com.example.dapp", name: "Example dApp")
)) { request in
    [
        "jsonrpc": "2.0", "id": request["id"] ?? .null,
        "error": ["code": -32601, "message": "Method not found"],
    ]
}

try await dapp.connect()
print(dapp.uri) // Share this pairing URI with the wallet.
try await dapp.waitForLink()
let response = try await dapp.send([
    "jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": [],
])
try await dapp.close()
```

## Wallet

```swift
let wallet = try await OpenLV.wallet(
    pairingURI,
    info: PeerInfo(identity: "com.example.wallet", name: "Example Wallet")
) { request in
    ["jsonrpc": "2.0", "id": request["id"] ?? .null, "result": "0x1"]
}
try await wallet.connect()
try await wallet.waitForLink()
// Keep the session alive while serving requests, then:
try await wallet.close()
```

For a runnable example, start `swift run openlv-example dapp` and then
`swift run openlv-example wallet 'openlv://…'` in another terminal.

## State, messages, and lifecycle

```swift
let changes = await wallet.states() // Subscribes immediately, before iteration.
let observer = Task {
    for try await state in changes {
        print(state.status, state.peer?.name ?? "")
    }
}
let current = try await wallet.state()
// Later:
observer.cancel()
```

Each `states()` call creates an independent subscription to future updates; use
`state()` for the current snapshot. Streams end when the native session closes.
Slow consumers can miss updates, matching the Rust broadcast stream. A final
`disconnected` update is not guaranteed; query `state()` after closing if needed.

`JSONValue` is `Codable` and `Sendable`, supports Swift JSON literals, and preserves
signed and unsigned 64-bit integers. Use `JSONValue(encoding: model)` and
`value.decode(Model.self)` to work with your own Codable types. Nonfinite numbers
fail encoding. Request handlers return the complete response; for JSON-RPC,
include `jsonrpc`, `id`, and `result` or `error`. The SDK does not implement wallet
authorization or Ethereum methods for you.

Handlers are `@Sendable`, may run concurrently, and should isolate mutable app
state in an actor. A thrown handler error fails the remote request immediately.
Handlers already running may finish after closing; stale replies are discarded.
`close()` shares one shutdown task across concurrent callers and cancels pending
native operations without waiting for app handlers. Call it explicitly when done;
deinitialization also starts best-effort shutdown. Swift task cancellation cancels
the corresponding UniFFI future without closing the whole session.

Failures are `OpenLVError` values with a typed `kind` and the original `nativeKind`
and message. Swift cancellation remains `CancellationError`. The default request
timeouts are 10 seconds for acknowledgement and one hour for the response after
acknowledgement. Override with `RequestTimeouts`; positive durations are truncated
to milliseconds, and durations smaller than one millisecond are rejected.

## Platforms and testing

Network-enabled apps need access to the signaling server and WebRTC sockets.
Sandboxed macOS apps need network client and server entitlements. iOS apps should
use HTTPS/WSS signaling endpoints; local-network testing may also require your
app's local-network privacy description and consent. Sessions do not provide an
iOS background-execution service; manage their lifecycle with your app.

`./scripts/test.sh` exercises the real native library offline, including URI handling,
validation, cancellation, close behavior, and JSON serialization. Opt into the
network test for bidirectional requests, concurrent handlers, handler failures,
timeouts, and closing pending requests:

```sh
OPENLV_LIVE_TESTS=1 ./scripts/test.sh --filter LiveSessionTests
# Optional local MQTT WebSocket broker:
OPENLV_LIVE_TESTS=1 OPENLV_TEST_MQTT_SERVER=ws://127.0.0.1:17887/mqtt \
  ./scripts/test.sh --filter LiveSessionTests
```

The test script supplies Swift Testing's framework path on Command Line Tools
installations; with full Xcode, `swift test` works directly.
The live test otherwise uses `https://ntfy.sh/` and public STUN infrastructure.
CI builds the macOS library and the full Apple XCFramework, runs offline tests,
and compiles the Swift package for iOS devices and Simulator. Live tests are opt-in.

## License

LGPL-3.0, consistent with the upstream Rust and Dart projects. See [LICENSE](LICENSE).
