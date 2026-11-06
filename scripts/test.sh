#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer="$(xcode-select -p)"
args=(--disable-xctest --enable-swift-testing)
if [[ "$developer" == */CommandLineTools ]]; then
  frameworks="$developer/Library/Developer/Frameworks"
  args+=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
  args+=(-Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib")
fi
exec swift test "${args[@]}" "$@"
