# iOS wallet demo

The app connects to an OpenLV dApp using a pasted pairing URI.

On a Mac with Xcode and Rust installed through rustup, build the framework and open the project:

```sh
scripts/build-native.sh
open Examples/iOS/OpenLVDemo.xcodeproj
```

Run the `OpenLVDemo` scheme on an iOS Simulator or device. Paste the dApp URI and tap **Connect**. The session screen shows the connection state; **Disconnect** closes it.

For the command-line demo on Linux, see the [repository README](../../README.md).
