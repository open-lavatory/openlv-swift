#!/bin/bash
# Build the Apple XCFramework.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
command -v cargo >/dev/null || { echo "Rust is required: https://rustup.rs" >&2; exit 1; }
command -v rustup >/dev/null || { echo "rustup is required to install Apple Rust targets: https://rustup.rs" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo "Apple XCFramework builds require macOS." >&2; exit 1; }
xcrun --sdk iphoneos --show-sdk-path >/dev/null
export MACOSX_DEPLOYMENT_TARGET=13.0
export IPHONEOS_DEPLOYMENT_TARGET=16.0
cargo build --manifest-path rust/Cargo.toml --locked --release --lib
mkdir -p .native-build/generated
(cd rust && cargo run --locked --features bindgen --bin uniffi-bindgen -- \
  generate --library target/release/libopenlv_swift_ffi.dylib \
  --crate openlv_ffi --language swift --config uniffi.toml \
  --out-dir ../.native-build/generated --no-format)
bash scripts/check-bindings.sh .native-build/generated/OpenLVNative.swift
mkdir -p .native-build/Headers
cp .native-build/generated/OpenLVFFI.h .native-build/Headers/
cp .native-build/generated/OpenLVFFI.modulemap .native-build/Headers/module.modulemap

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
echo "Built Native/OpenLVFFI.xcframework"
