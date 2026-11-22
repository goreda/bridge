#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"${SWIFTC:-swiftc}" -parse-as-library \
  "$root/Sources/GorAVPlaybackCore/PlayerControlPlane.swift" \
  "$root/Sources/GorAVPlaybackCore/MenuCapabilityPolicy.swift" \
  "$root/Tests/MenuCapabilityParity/MenuCapabilityPolicyTests.swift" \
  -o "$work/menu-capability-tests"
"$work/menu-capability-tests"
