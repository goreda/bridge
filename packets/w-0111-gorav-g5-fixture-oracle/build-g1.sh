#!/bin/sh
# build-g1.sh - seek-composition-tests (G1) on ohal/gorav @b3a2c4d, Linux, direct gcc/swiftc.
# Re-executed green by integrator 2026-10-26 (log g1-verify-run.log). Swift 6.1.2, FFmpeg 8.0.1@894da5ca static.
set -e
SW=${SW:-/tmp/swift-toolchain/swift-6.1.2-RELEASE-ubuntu22.04/usr/bin}
FF=${FF:-/tmp/s5work/FFmpeg-894da5ca7d742e4429ffb2af534fcda0103ef593}
ROOT=${ROOT:-/tmp/gorav-repo}; SRC=$ROOT/Sources; OBJ=${OBJ:-/tmp/g1-verify/obj}; LOG=${LOG:-/tmp/g1-verify}
mkdir -p "$OBJ" "$LOG"
ATX="-Xcc -fmodule-map-file=$SRC/GorAVCAtomics/module.modulemap -Xcc -I$SRC/GorAVCAtomics"
FFX="-Xcc -fmodule-map-file=$SRC/CFFmpeg/module.modulemap -Xcc -I$FF"
FFL="-L $FF/libavformat -L $FF/libavcodec -L $FF/libavutil -lavformat -lavcodec -lavutil -lm -lpthread -ldl"
gcc -O2 -fPIC -I$SRC/GorAVCAtomics -c $SRC/GorAVCAtomics/gorav_atomics.c -o $OBJ/gorav_atomics.o
gcc -shared $OBJ/gorav_atomics.o -o $OBJ/libGorAVCAtomics.so
$SW/swiftc -emit-library -emit-module -module-name GorAVCore $SRC/GorAVCore/Boundary.swift \
  -I $OBJ $ATX -L $OBJ -lGorAVCAtomics -o $OBJ/libGorAVCore.so -emit-module-path $OBJ/GorAVCore.swiftmodule
$SW/swiftc -emit-library -emit-module -module-name GorAVNativeProbeKit \
  $SRC/GorAVNativeProbeKit/GorAVSeekContract.swift $SRC/GorAVNativeProbeKit/NativeProbe.swift \
  $SRC/GorAVNativeProbeKit/LeaseTable.swift $SRC/GorAVNativeProbeKit/PacketFeedMachine.swift $SRC/GorAVNativeProbeKit/DemuxerPolicy.swift \
  -I $OBJ $ATX -L $OBJ -lGorAVCore -o $OBJ/libGorAVNativeProbeKit.so -emit-module-path $OBJ/GorAVNativeProbeKit.swiftmodule
$SW/swiftc -emit-library -emit-module -module-name GorAVFFmpegAdapter \
  $SRC/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift $SRC/GorAVFFmpegAdapter/SnapshotInput.swift \
  $SRC/GorAVFFmpegAdapter/SnapshotAVIOOwner.swift $SRC/GorAVFFmpegAdapter/FrameObservation.swift $SRC/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift \
  -I $OBJ $ATX $FFX -L $OBJ -lGorAVCore -lGorAVNativeProbeKit $FFL \
  -o $OBJ/libGorAVFFmpegAdapter.so -emit-module-path $OBJ/GorAVFFmpegAdapter.swiftmodule
$SW/swiftc -emit-library -emit-module -module-name GorAVPlaybackCore $SRC/GorAVPlaybackCore/*.swift \
  -I $OBJ $ATX -L $OBJ -lGorAVCore -lGorAVNativeProbeKit -lGorAVCAtomics \
  -o $OBJ/libGorAVPlaybackCore.so -emit-module-path $OBJ/GorAVPlaybackCore.swiftmodule
$SW/swiftc -emit-library -emit-module -module-name GorAVSeekComposition $SRC/GorAVSeekComposition/*.swift \
  -I $OBJ $ATX $FFX -L $OBJ -lGorAVCore -lGorAVNativeProbeKit -lGorAVFFmpegAdapter -lGorAVPlaybackCore $FFL \
  -o $OBJ/libGorAVSeekComposition.so -emit-module-path $OBJ/GorAVSeekComposition.swiftmodule
$SW/swiftc -parse-as-library $SRC/seek-composition-tests/SeekCompositionTests.swift \
  -I $OBJ $ATX $FFX -L $OBJ -lGorAVSeekComposition -lGorAVPlaybackCore -lGorAVFFmpegAdapter -lGorAVNativeProbeKit -lGorAVCore -lGorAVCAtomics $FFL \
  -o $OBJ/seek-composition-tests
timeout -k 5 300 env LD_LIBRARY_PATH=$OBJ GORAV_CANONICAL=$ROOT/fixtures/clip-bbb-10s.mov GORAV_OFFSET100=$ROOT/fixtures/clip-bbb-10s-audio-offset100ms.mov \
  $OBJ/seek-composition-tests > $LOG/g1-verify-run.log 2>&1
echo "run-exit=$? last=$(tail -1 $LOG/g1-verify-run.log)"
