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

## License

LGPL-3.0. See [LICENSE](LICENSE).
