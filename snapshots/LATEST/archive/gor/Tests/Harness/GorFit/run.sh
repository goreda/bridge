#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
source_file=${GOR_FIT_SOURCE:-"$here/../../../Sources/gor/Picture/Viewport.swift"}
swiftc=${SWIFTC:-swiftc}
out=${GOR_HARNESS_OUTPUT:-"$(mktemp -d "${TMPDIR:-/tmp}/gor-fit-d3-harness.XXXXXX")"}
mkdir -p "$out"
"$swiftc" --version
for suite in fit fence; do
  "$swiftc" -O "$source_file" "$here/$suite/main.swift" -o "$out/$suite"
  "$out/$suite" | tee "$out/$suite.log"
  grep -qx 'FAILS 0' "$out/$suite.log"
done
printf 'PASS: two recovered suites; logs retained at %s\n' "$out"
