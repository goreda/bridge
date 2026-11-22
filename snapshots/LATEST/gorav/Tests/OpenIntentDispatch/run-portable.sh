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
"$swiftc" -parse-as-library -D PORTABLE_INTENT_TEST -I "$work" -I "$root/Sources/GorAVCAtomics" \
 -L "$work" -lGorAVCore \
 "$root/Sources/GorAVPlaybackCore/OpenIntentClassification.swift" \
 "$root/Sources/GorAVPlaybackCore/OpenIntentDispatch.swift" \
 "$root/Tests/OpenIntentDispatch/DispatchTests.swift" -o "$work/tests"
LD_LIBRARY_PATH="$work:${LD_LIBRARY_PATH:-}" "$work/tests"
# Compile the actual conditional host file, not a copied shell or test double.
# On non-AppKit platforms it must be a valid empty module.
"$swiftc" -parse-as-library -emit-module -module-name EmbeddedConditionalHost \
 "$root/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift" \
 -emit-module-path "$work/EmbeddedConditionalHost.swiftmodule"
