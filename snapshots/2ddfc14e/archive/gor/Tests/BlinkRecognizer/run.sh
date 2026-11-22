#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$root/Sources/gor/Camera/BlinkEpisodes.swift" "$tmp/Extracted.swift" <<'PYEX'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text();i=s.index('struct BlinkEpisodeTracker {')
Path(sys.argv[2]).write_text('import Foundation\n'+s[i:])
PYEX
"${SWIFTC:-swiftc}" "$tmp/Extracted.swift" "$root/Tests/BlinkRecognizer/main.swift" -o "$tmp/test"
"$tmp/test"
