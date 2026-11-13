{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [ swift swiftpm pkg-config ];

  shellHook = ''
    set -e
    mkdir -p .build/generated .build/pkgconfig
    NIX_ENFORCE_PURITY=0 cargo build --locked --manifest-path rust/Cargo.toml
    (cd rust && cargo run --locked --features bindgen --bin uniffi-bindgen -- \
      generate --library target/debug/libopenlv_swift_ffi.so \
      --crate openlv_ffi --language swift --config uniffi.toml \
      --out-dir ../.build/generated --no-format)
    cat > .build/pkgconfig/openlv-ffi.pc <<EOF
libdir=$PWD/rust/target/debug
Name: openlv-ffi
Description: OpenLV UniFFI bridge
Version: 0.2.0
Libs: -L$PWD/rust/target/debug -lopenlv_swift_ffi
EOF
    export PKG_CONFIG_PATH="$PWD/.build/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="$PWD/rust/target/debug''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';
}
