#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$root"
# These are only pure playback/atomic dependencies, never decoder/network/process sources.
for file in SPSC.swift TimingLedger.swift Lane0Contract.swift; do
    git show "HEAD:Sources/GorAVPlaybackCore/$file" > "$work/$file"
done
for file in gorav_atomics.c gorav_atomics.h module.modulemap; do
    git show "HEAD:Sources/GorAVCAtomics/$file" > "$work/$file"
done
${CC:-clang} -std=c11 -c "$work/gorav_atomics.c" -o "$work/atomics.o"
${SWIFTC:-swiftc} -parse-as-library -I "$work" \
    Sources/GorAVPlaybackCore/PlaybackCore.swift Sources/GorAVPlaybackCore/NativeFrameOwnership.swift \
    "$work/SPSC.swift" "$work/TimingLedger.swift" "$work/Lane0Contract.swift" \
    Tests/VTProducer/VTProducerTests.swift "$work/atomics.o" -o "$work/tests"
"$work/tests"
