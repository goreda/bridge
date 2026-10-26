#!/bin/bash
# W-108r2 stage-2: self-contained NH6 hold-test validation (credential-free).
# Layout is bundle-relative. Expects FFmpeg libs per ffmpeg/RECIPE.md at $FF_KIT
# (default: ffmpeg/build). Linux, Swift 6.1.2. Expected: FINAL pass=41 fail=0, zero gate-timeout lines.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SWIFTC="${SWIFTC:-swiftc}"; CC="${CC:-cc}"
FF="${FF_KIT:-$ROOT/ffmpeg/build}"
FIXTURE="$ROOT/fixtures/fixture.mov"
for l in libavformat libavcodec libavutil; do
  [ -f "$FF/$l/$l.a" ] || { echo "MISSING $FF/$l/$l.a - build FFmpeg per ffmpeg/RECIPE.md (or set FF_KIT)"; exit 2; }
done
[ -f "$FIXTURE" ] || { echo "MISSING fixture $FIXTURE"; exit 2; }
echo "== pin check =="
(cd "$ROOT" && sha256sum -c MANIFEST.sha256 --quiet) || { echo "PIN MISMATCH - aborting"; exit 2; }
TREE="$ROOT/.stage2-tree"; OBJ="$ROOT/.stage2-obj"
rm -rf "$TREE" "$OBJ"; mkdir -p "$TREE" "$OBJ"
cp -r "$ROOT/base/Sources" "$TREE/Sources"
# stage-2 overlays: contract candidate (module source) + DIAGNOSTIC decoder (test-build overlay ONLY)
cp "$ROOT/candidates/contract-candidate.swift" "$TREE/Sources/GorAVNativeProbeKit/GorAVSeekContract.swift"
cp "$ROOT/candidates/diag-candidate.swift"     "$TREE/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift"
mkdir -p "$TREE/Sources/native-hold-tests"
cp "$ROOT/candidates/suite-candidate-v2.swift" "$TREE/Sources/native-hold-tests/main.swift"
S="$TREE/Sources"
ATX="-Xcc -fmodule-map-file=$S/GorAVCAtomics/module.modulemap -Xcc -I$S/GorAVCAtomics"
FFX="-Xcc -fmodule-map-file=$S/CFFmpeg/module.modulemap -Xcc -I$FF"
FFL="-L $FF/libavformat -L $FF/libavcodec -L $FF/libavutil -lavformat -lavcodec -lavutil -lm -lpthread -ldl"
echo "== build: atomics =="
$CC -O2 -fPIC -I$S/GorAVCAtomics -c $S/GorAVCAtomics/gorav_atomics.c -o $OBJ/gorav_atomics.o
$CC -shared $OBJ/gorav_atomics.o -o $OBJ/libGorAVCAtomics.so
echo "== build: modules =="
$SWIFTC -emit-library -emit-module -module-name GorAVCore $S/GorAVCore/Boundary.swift -I $OBJ $ATX -L $OBJ -lGorAVCAtomics -o $OBJ/libGorAVCore.so -emit-module-path $OBJ/GorAVCore.swiftmodule
$SWIFTC -emit-library -emit-module -module-name GorAVNativeProbeKit $S/GorAVNativeProbeKit/*.swift -I $OBJ $ATX -L $OBJ -lGorAVCore -o $OBJ/libGorAVNativeProbeKit.so -emit-module-path $OBJ/GorAVNativeProbeKit.swiftmodule
$SWIFTC -emit-library -emit-module -module-name GorAVFFmpegAdapter $S/GorAVFFmpegAdapter/*.swift -I $OBJ $ATX $FFX -L $OBJ -lGorAVCore -lGorAVNativeProbeKit -lGorAVCAtomics $FFL -o $OBJ/libGorAVFFmpegAdapter.so -emit-module-path $OBJ/GorAVFFmpegAdapter.swiftmodule
echo "== build: suite =="
$SWIFTC -parse-as-library $S/native-hold-tests/main.swift -I $OBJ $ATX $FFX -L $OBJ -lGorAVFFmpegAdapter -lGorAVNativeProbeKit -lGorAVCore -lGorAVCAtomics $FFL -o $OBJ/native-hold-tests
echo "== run: NH6 explicit selector =="
LOG="$ROOT/stage2-run.log"
S5_SEEK_FIXTURE="$FIXTURE" LD_LIBRARY_PATH="$OBJ" timeout -k 5 180 "$OBJ/native-hold-tests" NH6 2>&1 | tee "$LOG" || true
echo "== verdict =="
GT=$(grep -c "gate-timeout" "$LOG" || true)
FINAL=$(grep "^FINAL" "$LOG" || echo "FINAL MISSING")
echo "gate-timeout lines: $GT"
echo "$FINAL"
[ "$GT" = "0" ] && [ "$FINAL" = "FINAL pass=41 fail=0" ] && echo "STAGE2_VERDICT: PASS (41/0, zero gate-timeout)" || { echo "STAGE2_VERDICT: FAIL"; exit 1; }
