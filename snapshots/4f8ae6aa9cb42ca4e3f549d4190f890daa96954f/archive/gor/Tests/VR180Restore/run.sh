#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$HERE/../../Sources/gor/Stereo/StereoDetection.swift" "$TMP/Extracted.swift" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text();s=s[:s.index('    static func inspect')]+'}\n'
Path(sys.argv[2]).write_text(s)
PY
python3 - "$(python3 -c "import importlib.util as u,sys;s=u.spec_from_file_location('t',sys.argv[1]);m=u.module_from_spec(s);s.loader.exec_module(m);print(m.path(sys.argv[2]))" "$HERE/../Structure/threed_split.py" "$HERE/../..")" "$TMP/ThreeDState.swift" <<'PY'
import sys,pathlib
b=pathlib.Path(sys.argv[1]).read_text()
n='ThreeDState.swift'
pathlib.Path(sys.argv[2]).write_text(b[b.index('// BEGIN relocated '+n+' '):b.index('// END relocated '+n+'\n')])
PY
"${SWIFTC:-swiftc}" "$TMP/Extracted.swift" "$HERE/../../Sources/gor/Stereo/StereoGeometry.swift" "$TMP/ThreeDState.swift" "$HERE/main.swift" -o "$TMP/check"
"$TMP/check"
