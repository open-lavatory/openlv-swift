#!/bin/bash
# Check the Swift source compiled by SwiftPM against fresh UniFFI output.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
generated="${1:?Usage: bash scripts/check-bindings.sh GENERATED_SWIFT_FILE}"
source="$root/Sources/OpenLVNative/OpenLVNative.swift"
[[ -f "$generated" ]] || { echo "Generated bindings not found: $generated" >&2; exit 1; }
# UniFFI omits the final newline; normalize that alone for the comparison.
if ! diff -u <(awk '1' "$source") <(awk '1' "$generated"); then
    echo "Swift bindings are stale. Copy $generated to $source and rebuild." >&2
    exit 1
fi
