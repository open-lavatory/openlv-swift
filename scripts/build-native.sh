#!/bin/bash
# Build the local XCFramework before opening Package.swift or running swift test.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mode="${1:---host}"
[[ "$(uname -s)" == Darwin ]] || { echo "Apple native builds require macOS." >&2; exit 1; }
case "$mode" in
  --host|--all) ;;
  *) echo "Usage: $0 [--host|--all]" >&2; exit 64 ;;
esac
command -v cargo >/dev/null || { echo "Rust is required: https://rustup.rs" >&2; exit 1; }
if [[ "$mode" == --all ]]; then
  xcrun --sdk iphoneos --show-sdk-path >/dev/null
fi
export MACOSX_DEPLOYMENT_TARGET=13.0
export IPHONEOS_DEPLOYMENT_TARGET=16.0
cargo build --manifest-path rust/Cargo.toml --locked --release --lib
mkdir -p .native-build/generated
(cd rust && cargo run --locked --features bindgen --bin uniffi-bindgen -- \
  generate --library target/release/libopenlv_swift_ffi.dylib \
  --crate openlv_ffi --language swift --config uniffi.toml \
  --out-dir ../.native-build/generated --no-format)
cp .native-build/generated/OpenLVNative.swift Sources/OpenLVNative/OpenLVNative.swift
python3 scripts/patch-swift-cancellation.py Sources/OpenLVNative/OpenLVNative.swift
mkdir -p .native-build/Headers
cp .native-build/generated/OpenLVFFI.h .native-build/Headers/
cp .native-build/generated/OpenLVFFI.modulemap .native-build/Headers/module.modulemap

if [[ "$mode" == --all ]]; then
  targets=(aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
  for target in "${targets[@]}"; do
    rustup target add "$target"
    cargo build --manifest-path rust/Cargo.toml --locked --release --lib --target "$target"
  done
  mkdir -p .native-build/macos .native-build/ios-simulator
  lipo -create rust/target/{aarch64-apple-darwin,x86_64-apple-darwin}/release/libopenlv_swift_ffi.a \
    -output .native-build/macos/libopenlv_swift_ffi.a
  lipo -create rust/target/{aarch64-apple-ios-sim,x86_64-apple-ios}/release/libopenlv_swift_ffi.a \
    -output .native-build/ios-simulator/libopenlv_swift_ffi.a
  rm -rf Native/OpenLVFFI.xcframework
  xcodebuild -create-xcframework \
    -library .native-build/macos/libopenlv_swift_ffi.a -headers .native-build/Headers \
    -library rust/target/aarch64-apple-ios/release/libopenlv_swift_ffi.a -headers .native-build/Headers \
    -library .native-build/ios-simulator/libopenlv_swift_ffi.a -headers .native-build/Headers \
    -output Native/OpenLVFFI.xcframework
else
  # A host-only XCFramework also works with Command Line Tools (no full Xcode).
  arch="$(uname -m)"
  case "$arch" in arm64|x86_64) ;; *) echo "Unsupported macOS architecture: $arch" >&2; exit 1 ;; esac
  python3 scripts/package-host.py "$arch"
fi
echo "Built Native/OpenLVFFI.xcframework ($mode)"
