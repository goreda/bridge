#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
# Actual production parser only, removing Darwin-dependent process invocation.
python3 - "$HERE/../../Sources/gor/Stereo/StereoDetection.swift" "$TMP/Extracted.swift" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
s=s[:s.index('    static func inspect')]+'}\n'
s=s.replace('import Darwin\n','')
Path(sys.argv[2]).write_text(s)
PY
"${SWIFTC:-swiftc}" "$TMP/Extracted.swift" "$HERE/../../Sources/gor/Stereo/StereoGeometry.swift" "$HERE/main.swift" -o "$TMP/check"
"$TMP/check"
