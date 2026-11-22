#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"${SWIFTC:-swiftc}" "$root/Sources/gor/GorFit.swift" "$root/Tests/CropOwner/main.swift" -o "$tmp/test"
"$tmp/test"
