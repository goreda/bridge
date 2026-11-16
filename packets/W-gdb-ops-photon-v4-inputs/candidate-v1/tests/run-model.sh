#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD=${PHOTON_BUILD:-/tmp/photon-v4-model}; mkdir -p "$BUILD"
CC=${CC:-/home/sandbox/swift/usr/bin/clang}
SWIFTC=${SWIFTC:-/home/sandbox/swift/usr/bin/swiftc}
"$CC" photon-v4/tests/lua51.c -Wl,-l:liblua5.1.so.0 -o "$BUILD/lua51"
"$BUILD/lua51" photon-v4/tests/test-model.lua > "$BUILD/lua.out"
"$SWIFTC" photon-v4/swift/PhotonV4Model.swift photon-v4/tests/main.swift -o "$BUILD/model"
"$BUILD/model" > "$BUILD/swift.out"
diff -u "$BUILD/lua.out" "$BUILD/swift.out"
printf 'Lua51/Swift parity: %s vectors; invalid/zero cases passed\n' "$(wc -l < "$BUILD/lua.out")"
