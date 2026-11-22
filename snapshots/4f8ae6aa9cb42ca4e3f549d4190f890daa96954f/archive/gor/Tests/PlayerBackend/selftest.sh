#!/bin/bash
# Optional E1 hook, not part of delivery-gate183. Never fetch/build GorAV implicitly.
set -eu
[ "${GOR_ENGINE:-mpv}" = gorav ] || { echo 'SKIP gorav E1: engine is mpv'; exit 0; }
root=${GORAV_ENGINE_ROOT:-}
asserts=${GORAV_E1_ASSERTS:-}
if [ -z "$asserts" ] || [ ! -f "$asserts" ]; then
    echo 'E1 asserts: not yet on trunk'
    exit 0
fi
# The engine checkout and exact command must be explicit until trunk publishes
# its E1 assertion entry point. Do not equate an existing package with E1 PASS.
[ -n "$root" ] && [ -f "$root/Package.swift" ] || { echo 'FAIL gorav-e1: GORAV_ENGINE_ROOT must name the engine checkout'; exit 1; }
echo "gorav E1 asserts: $asserts"
if (cd "$root" && bash "$asserts"); then
    echo 'PASS gorav-e1 asserts (optional; not a delivery gate)'
else
    echo 'FAIL gorav-e1 asserts (optional; not a delivery gate)'
    exit 1
fi
