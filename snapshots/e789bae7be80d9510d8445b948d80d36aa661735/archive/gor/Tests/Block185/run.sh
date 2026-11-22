#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"${SWIFTC:-swiftc}" "$ROOT/Sources/gor/Camera/HeadPose.swift" "$ROOT/Sources/gor/Stereo/StereoDetection.swift" "$ROOT/Sources/gor/Stereo/StereoGeometry.swift" "$ROOT/Tests/Support/StereoDetectionBoundary.swift" "$HERE/main.swift" -o "$TMP/check"
"$TMP/check"
python3 "$HERE/capture.py"

python3 "$HERE/pose-routing.py"

python3 "$HERE/geometry-routing.py"
cp "$HERE/geometry-window.swift" "$TMP/main.swift"
"${SWIFTC:-swiftc}" "$ROOT/Sources/gor/Stereo/StereoGeometry.swift" "$ROOT/Sources/gor/GorFit.swift" "$TMP/main.swift" -o "$TMP/window"
"$TMP/window"

python3 "$HERE/geometry-mode-switch.py"
