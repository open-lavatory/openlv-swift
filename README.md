<p align="center">
  <a href="https://openlv.sh">
    <picture>
      <source srcset="https://raw.githubusercontent.com/v3xlabs/open-lavatory/refs/heads/master/docs/public/openlv_logo_dark.svg" media="(prefers-color-scheme: dark)">
      <img src="https://raw.githubusercontent.com/v3xlabs/open-lavatory/refs/heads/master/docs/public/openlv_logo_light.svg" alt="Open Lavatory" height="60">
    </picture>
  </a>
</p>

<p align="center">Connect Swift wallets to OpenLV dApps</p>

# OpenLV for Swift

Add OpenLV wallet connectivity to a Swift app with [OpenLV](https://openlv.sh).

On Linux, install Rust 1.91 or newer with Cargo before entering the Nix shell.
The shell supplies Swift and pkg-config and builds the native Rust library.

```sh
nix-shell
swift run openlv-example wallet 'openlv://…'
```

## Add a wallet to your app

Pass the dApp's pairing URI to `OpenLV.wallet` and handle incoming requests:

```swift
import OpenLV

let wallet = try await OpenLV.wallet(
    pairingURI,
    info: PeerInfo(identity: "com.example.wallet", name: "Example Wallet")
) { request in
    [
        "jsonrpc": "2.0",
        "id": request["id"] ?? .null,
        "error": ["code": -32601, "message": "Method not found"],
    ]
}

try await wallet.connect()
try await wallet.waitForLink()
try await wallet.close()
```

The [iOS demo](Examples/iOS/README.md) is a wallet app.

## Create a dApp session

Supply the signaling protocol and server explicitly, matching the Rust and JS
session APIs.

Supported protocols are `.ntfy`, `.mqtt`, and `.nostr`.

```swift
let dapp = try await OpenLV.dapp(
    options: DappOptions(protocol: .ntfy, server: "https://ntfy.sh/")
) { request in
    ["jsonrpc": "2.0", "id": request["id"] ?? .null, "result": "ok"]
}
```

The command-line example accepts the same settings:

```sh
swift run openlv-example dapp ntfy 'https://ntfy.sh/'
```

## Session lifetime

Call `try await session.close()` when finished. Closing releases pending native
operations and ends all state streams. Concurrent and repeated close calls share
the same shutdown operation.

UniFFI 0.32.2 does not propagate Swift task cancellation to pending Rust calls.
Cancelling a task waiting on `states()` can leave it suspended until the next
state change or session shutdown. Close the session before awaiting a cancelled
observer; cancelling the observer alone does not release its native wait.

## iOS demo

Use a Mac with Xcode and Rust installed through rustup. The build script installs
the required Apple Rust targets through rustup.

```sh
scripts/build-native.sh
open Examples/iOS/OpenLVDemo.xcodeproj
```

Select the `OpenLVDemo` scheme and an iOS Simulator or device. The [GitHub Actions build](.github/workflows/ci.yml) also builds the Apple framework and uploads it as an Actions artifact.

## SwiftPM packaging

`Package.swift` currently points to `Native/OpenLVFFI.xcframework`, which is built locally and ignored by Git. Build it with `scripts/build-native.sh` before building the package on macOS. The CI artifact is not a remote SwiftPM binary release, so this repository is not yet installable as a remote SwiftPM dependency from a clean checkout.

## Development checks

On Linux, enter the Nix shell, then run:

```sh
bash scripts/check-bindings.sh .build/generated/OpenLVNative.swift
swift test
```

On macOS, run `scripts/build-native.sh` and then `swift test`. The build script
checks the generated bindings automatically. The tests exercise the real native
library. The ordinary suite does not connect to a server.

To also test a real handshake, requests in both directions, peer metadata, and
handler failures, start a local MQTT broker and opt in:

```sh
OPENLV_TEST_MQTT_SERVER=mqtt://127.0.0.1:21883 swift test
```

The broker is a test prerequisite only; it is not an SDK dependency. With
Mosquitto already installed, `mosquitto -p 21883` starts a local-only broker.

The binding check compares fresh UniFFI output with
`Sources/OpenLVNative/OpenLVNative.swift`. If it fails after a Rust API or UniFFI
version change, copy the generated Swift file from the path in the error message
into that source file, then rebuild and run the tests.

## License

LGPL-3.0. See [LICENSE](LICENSE).
