#!/bin/sh
# Byte-equality gate: the kit's staged production sources must match the pinned
# production paths byte for byte before swift build/test runs.
set -e
KIT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$KIT/../../.." && pwd)"
for f in ArchiveItemSource.swift CacheAccounting.swift; do
    if ! cmp -s "$KIT/Sources/GorAVPlaybackCore/$f" "$ROOT/Sources/GorAVPlaybackCore/$f"; then
        echo "PIN_MISMATCH $f" >&2
        exit 1
    fi
done
echo "PIN_BYTES_MATCH 199r-1nstinct-02"
