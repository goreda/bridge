#!/usr/bin/env bash
set -euo pipefail
[ "$#" -gt 0 ] || { printf "usage: run-portable.sh fixture...\n" >&2; exit 2; }
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
prefix=$(git rev-parse --show-prefix)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Build the real demux/E1/audio state-machine paths only. No product decoder
# source or decoder close-order implementation is loaded by this harness.
copy_tree() {
    local directory=$1
    mkdir -p "$work/$directory"
    while IFS= read -r file; do
        relative=${file#"$prefix"}
        git show "HEAD:$file" > "$work/$relative"
    done < <(git ls-tree -r --name-only HEAD -- "$prefix$directory")
}
copy_tree Tests/labs/p-a1-r2/Sources/BridgeDemux
copy_tree Sources/AudioMasterScheduler
copy_tree Sources/CFFmpeg
for file in Sources/GorAVPlaybackCore/LabPGSDecoder.swift Sources/GorAVPlaybackCore/LabSwrConverter.swift Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift Sources/GorAVFFmpegAdapter/LabSwrBackendBinding.swift; do
    mkdir -p "$work/$(dirname "$file")"
    git show "HEAD:${prefix}$file" > "$work/$file"
done
: "${FFMPEG_INCLUDE:?Set verified FFmpeg include directory}"
: "${FFMPEG_LIB:?Set verified FFmpeg library directory}"
compiler=${SWIFTC:-swiftc}
extra=()
if [ -n "${DAV1D_LIB:-}" ]; then extra=(-L "$DAV1D_LIB" -ldav1d); fi
"$compiler" -emit-module -emit-library -module-name BridgeDemux "$work"/Tests/labs/p-a1-r2/Sources/BridgeDemux/*.swift -emit-module-path "$work/BridgeDemux.swiftmodule" -o "$work/libBridgeDemux.so"
"$compiler" -emit-module -emit-library -module-name AudioMasterScheduler "$work"/Sources/AudioMasterScheduler/*.swift -emit-module-path "$work/AudioMasterScheduler.swiftmodule" -o "$work/libAudioMasterScheduler.so"
"$compiler" -emit-module -emit-library -module-name GorAVPlaybackCore "$work"/Sources/GorAVPlaybackCore/*.swift -emit-module-path "$work/GorAVPlaybackCore.swiftmodule" -o "$work/libGorAVPlaybackCore.so"
"$compiler" -emit-module -emit-library -module-name GorAVFFmpegAdapter -I "$work" -I "$work/Sources/CFFmpeg" -Xcc -I"$FFMPEG_INCLUDE" -L "$work" -lGorAVPlaybackCore -L "$FFMPEG_LIB" "${extra[@]}" "$work/Sources/GorAVFFmpegAdapter/LabSwrBackendBinding.swift" -emit-module-path "$work/GorAVFFmpegAdapter.swiftmodule" -o "$work/libGorAVFFmpegAdapter.so"
"$compiler" -I "$work" -I "$work/Sources/CFFmpeg" -Xcc -I"$FFMPEG_INCLUDE" -L "$work" -lBridgeDemux -lAudioMasterScheduler -lGorAVPlaybackCore -lGorAVFFmpegAdapter -L "$FFMPEG_LIB" "${extra[@]}" Sources/e1-headless-tests/main.swift Sources/e1-headless-tests/presenter-mac.swift -o "$work/e1"
export LD_LIBRARY_PATH="$work${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
for fixture in "$@"; do
    set +e
    "$work/e1" "$fixture"
    rc=$?
    set -e
    printf 'FIXTURE_EXIT=%s path=%s\n' "$rc" "$fixture"
    # 77 is native-only UNRUN after the portable assertions pass, never PASS.
    if [ "$rc" -ne 77 ]; then exit 1; fi
done
set +e
E1_SIM_AUDIO_CLOCK=1 E1_SIM_SLOW_FRAME_MS=120 E1_SIM_SLOW_FRAME_IDX=10 "$work/e1" "$1"
rc=$?
set -e
printf 'SLOW_WITNESS_EXIT=%s\n' "$rc"
[ "$rc" -eq 1 ]
printf 'PORTABLE_RECEIPT=complete; native Darwin/Metal/audio/VT UNRUN\n'
