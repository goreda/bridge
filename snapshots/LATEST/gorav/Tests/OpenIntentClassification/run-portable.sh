#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cc=${CC:-clang}
swiftc=${SWIFTC:-swiftc}
"$cc" -std=c11 -c "$root/Sources/GorAVCAtomics/gorav_atomics.c" -o "$work/atomics.o"
"$swiftc" -parse-as-library -emit-module -emit-library -module-name GorAVCore \
 -I "$root/Sources/GorAVCAtomics" \
 "$root/Sources/GorAVCore/Boundary.swift" \
 "$root/Sources/GorAVCore/AdmissionTable.swift" \
 "$root/Sources/GorAVCore/OpenURLRouter.swift" "$work/atomics.o" \
 -emit-module-path "$work/GorAVCore.swiftmodule" -o "$work/libGorAVCore.so"
"$swiftc" -parse-as-library -I "$work" -I "$root/Sources/GorAVCAtomics" \
 -L "$work" -lGorAVCore \
 "${INTENT_SOURCE:-$root/Sources/GorAVPlaybackCore/OpenIntentClassification.swift}" \
 "$root/Tests/OpenIntentClassification/ClassificationTests.swift" -o "$work/tests"
LD_LIBRARY_PATH="$work:${LD_LIBRARY_PATH:-}" "$work/tests"
