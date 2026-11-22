#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
prefix=$(git rev-parse --show-prefix)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for file in SPSC.swift TimingLedger.swift Lane0Contract.swift; do
    git show "HEAD:${prefix}Sources/GorAVPlaybackCore/$file" > "$work/$file"
done
for file in gorav_atomics.c gorav_atomics.h module.modulemap; do
    git show "HEAD:${prefix}Sources/GorAVCAtomics/$file" > "$work/$file"
done
${CC:-clang} -std=c11 -fPIC -c "$work/gorav_atomics.c" -o "$work/atomics.o"
${SWIFTC:-swiftc} -emit-module -emit-library -module-name GorAVPlaybackCore -I "$work" \
    Sources/GorAVPlaybackCore/PlaybackCore.swift Sources/GorAVPlaybackCore/NativeFrameOwnership.swift \
    "$work/SPSC.swift" "$work/TimingLedger.swift" "$work/Lane0Contract.swift" "$work/atomics.o" \
    -emit-module-path "$work/GorAVPlaybackCore.swiftmodule" -o "$work/libGorAVPlaybackCore.so"
: "${CFFMPEG_MODULE:?Set existing CFFmpeg module directory}"
: "${FFMPEG_INCLUDE:?Set verified provider include directory}"
: "${FFMPEG_LIB:?Set verified provider library directory}"
extra=()
if [ -n "${DAV1D_LIB:-}" ]; then extra=(-L "$DAV1D_LIB" -ldav1d); fi
${SWIFTC:-swiftc} -D DEBUG -parse-as-library -I "$work" -I "$CFFMPEG_MODULE" \
    -Xcc -I"$FFMPEG_INCLUDE" -L "$work" -lGorAVPlaybackCore -L "$FFMPEG_LIB" "${extra[@]}" \
    Sources/GorAVFFmpegAdapter/VTHardwareFrameProducer.swift Tests/VTPublicProducer/ProducerTests.swift \
    -o "$work/tests"
LD_LIBRARY_PATH="$work${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$work/tests" "$1"
