# OpenLV iOS demo

A SwiftUI test app for iPhone and iPad (iOS 16+, Xcode 16+). It uses the local
`OpenLV` package from this checkout; no Xcode project generator is required.

## Run

From the repository root on a Mac with full Xcode selected:

```sh
./scripts/build-native.sh --all
open Examples/iOS/OpenLVDemo.xcodeproj
```

Build the native framework **before** opening the project. The `--host` build
contains only macOS code and cannot link this app; rerun `--all` if needed.
Select the **OpenLVDemo** scheme and an iOS Simulator, then Run. For a physical
device, select your development team under Signing & Capabilities and choose a
unique bundle identifier if required. No team is committed to the project.

## Test on one device

1. Leave **dApp** selected and tap **Start dApp**.
2. Once signaling starts, tap **Pair demo wallet**. Wait for both sessions to show
   `connected`. This creates a second real native session, not a mocked transport.
3. Tap **Send request**. The traffic log should show `eth_chainId` returning `0x1`.
4. Load **Echo** and send it. **Send from demo wallet** tests the reverse direction.
5. Load **Five-second delay** and set the response timeout to 1 second to exercise
   `request_timeout`. With a longer timeout, use **Cancel** while a request is
   pending, then send another request to check that the connection remains usable.
6. Tap **Disconnect** during pairing or a pending request to exercise shutdown.
   Start again to create a new session.

Both peers require internet access: the default configuration uses public ntfy
signaling and STUN services. A failure to connect can reflect network or service
availability; inspect the signaling state and errors in the log.

## Test with another peer

Start the dApp and copy or share its pairing URI. On another foreground iOS demo
instance, select **Wallet**, paste the URI, and tap **Connect wallet**. Pair only
one wallet to a dApp session. You can also pair the app with the command-line demo:

```sh
# Pair a command-line wallet with the iOS dApp:
swift run openlv-example wallet 'openlv://…'

# Or start a command-line dApp and paste its printed URI into the iOS wallet:
swift run openlv-example dapp
```

The command-line demo handles `eth_chainId`; use the two iOS peers for echo/delay
responses. A command-line dApp closes after receiving its first response.

The pairing URI contains a secret. The app does not deliberately add it to the
traffic log or persist it. The Copy button uses a local-only clipboard entry that
expires after five minutes. Share it only with your test peer. Request and response
contents are visible in the in-memory log (latest 100 events).

## Lifecycle and behavior

The app subscribes to `states()` before connecting, queries `state()` for snapshots,
and explicitly closes both sessions on Disconnect or when its scene enters the
background. Keep both apps visible while testing; returning to the foreground
requires starting/pairing again. Opening the share sheet can interrupt a test if
the app subsequently backgrounds. No background execution mode is enabled.
Allow local-network access if iOS prompts for it. The project includes a local-network
usage description and uses the library's default secure signaling configuration.

Both in-app handlers return complete JSON-RPC responses for these test methods:

- `eth_chainId`: static result `"0x1"` (no chain connection).
- `demo_echo`: returns the supplied `params` value.
- `demo_delay`: returns after five seconds; useful for cancellation and timeout tests.
- Other methods: error `-32601` (method not found).

These are test responses only. The app has no wallet keys, account authorization,
signing, transaction submission, or QR/deep-link handling. Paste a pairing URI
explicitly. A locally cancelled/timed-out request can still finish its remote handler;
the library discards stale replies.

## Build without signing

After building the full native framework, CI and local Xcode installations can
compile and link the app with:

```sh
xcodebuild -project Examples/iOS/OpenLVDemo.xcodeproj -scheme OpenLVDemo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/demo-simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Examples/iOS/OpenLVDemo.xcodeproj -scheme OpenLVDemo \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/demo-device CODE_SIGNING_ALLOWED=NO build
```

CI builds do not launch the app. Live Simulator/device sessions and background
transitions still require running the manual checks above.
