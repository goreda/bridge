#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"${SWIFTC:-swiftc}" "$root/Sources/gor/App/IndependentDocumentRouter.swift" \
 "$root/Tests/IndependentDocuments/main.swift" -o "$work/router-tests"
"$work/router-tests"
