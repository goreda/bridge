#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FFMPEG=${FFMPEG:-$ROOT/Resources/vendor/ffmpeg/bin/ffmpeg}
# Original decoded luma, with a ONE-PIXEL bright feature before lossless encoding.
python3 - "$TMP" <<'PY'
import sys,pathlib
p=pathlib.Path(sys.argv[1]);w,h=128,96
v=bytearray([16]*(w*h))
for y in range(20,76): v[y*w:(y+1)*w]=bytes([235])*w
(p/'plain.y').write_bytes(v)
v[2*w+10]=235
(p/'bright.y').write_bytes(v)
PY
for fixture in plain bright; do
 "$FFMPEG" -v error -f rawvideo -pixel_format gray -video_size 128x96 -i "$TMP/$fixture.y" -frames:v 1 -c:v ffv1 -pix_fmt gray "$TMP/$fixture.mkv"
 "$FFMPEG" -v error -i "$TMP/$fixture.mkv" -frames:v 1 -pix_fmt gray16le -f rawvideo "$TMP/$fixture.16"
done
python3 - "$(python3 -c "import importlib.util as u,sys;s=u.spec_from_file_location('t',sys.argv[1]);m=u.module_from_spec(s);s.loader.exec_module(m);print(m.path(sys.argv[2]))" "$ROOT/Tests/Structure/threed_split.py" "$ROOT")" "$TMP/Bounds.swift" <<'PY'
import sys,pathlib
b=pathlib.Path(sys.argv[1]).read_text()
n='SourcePixelCrop.swift'
s=b[b.index('// BEGIN relocated '+n+' '):b.index('// END relocated '+n+'\n')]
s=s.split('final class SourcePixelCropScanner')[0].replace('import Darwin\n','')
pathlib.Path(sys.argv[2]).write_text(s)
PY
"${SWIFTC:-swiftc}" "$ROOT/Sources/gor/Camera/HeadPose.swift" "$ROOT/Sources/gor/Stereo/StereoGeometry.swift" "$TMP/Bounds.swift" "$HERE/main.swift" -o "$TMP/check"
"$TMP/check" "$TMP/plain.16" "$TMP/bright.16"
# Ownership is also checked against actual production routing, not a copied policy fixture.
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
import importlib.util as iu
r=Path(sys.argv[1]);_sp=iu.spec_from_file_location('pp_split',r/'Tests/Structure/pp_split.py');_pp=iu.module_from_spec(_sp);_sp.loader.exec_module(_pp)
_sub_spec=iu.spec_from_file_location('subtitles_block184',r/'Tests/Structure/subtitles_source.py');_sub_view=iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
s=_pp.path(r,'PPController.swift').read_text();v=_sub_view.unit_text('SubtitleView.swift',r)
assert 'set_property","sub-visibility",false' in s
assert 'setNativeSubtitleRendererActive(nativeReported)' in s
assert 'CATransform3DMakeTranslation(shiftX + (on ? offsetX : 0), 0, 0)' in v
print('PASS 184-3 source ownership OFF-before-custom and horizontal-only replica (static; native pixels unrun)')
PY
