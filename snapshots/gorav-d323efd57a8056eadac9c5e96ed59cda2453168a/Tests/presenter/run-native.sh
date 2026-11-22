#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
if [ "$(uname -s)" != Darwin ]; then
  echo 'G3 AppKit geometry: UNRUN (requires macOS)' >&2
  exit 77
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import sys
root, tmp = map(Path, sys.argv[1:])
s = (root/'Sources/GorAVMetalPresenter/core/MetalPresenter.swift').read_text()
a = s.index('public final class MetalPresenterView: NSView {')
b = s.index('\n/// FrameSink conformance', a)
(tmp/'MetalPresenterView.swift').write_text('import AppKit\nimport QuartzCore\n'+s[a:b])
PY
swiftc -parse-as-library "$TMP/MetalPresenterView.swift" "$ROOT/Tests/presenter/EmbeddingGeometryTests.swift" -o "$TMP/geometry-test"
"$TMP/geometry-test"
