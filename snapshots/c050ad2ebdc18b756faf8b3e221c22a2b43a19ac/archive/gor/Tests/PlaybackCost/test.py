"""Instrumentation contract tests, not proof of on-Mac playback improvement."""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('capture.py'))
capture = importlib.util.module_from_spec(spec); spec.loader.exec_module(capture)
line = '14:30:01 playback-cost gor=4.5 mpv=96.1 ffmpeg=210.2 ffmpegWorkers=2 sampleEvery_s=10 metric=ps_cpu_percent'
assert capture.extract(line + ' secret=/private/media.mov') == [line]
thermal = '[thermal-diag] mpvPID=123 generation=1 hwdec=auto hwdec-current=videotoolbox vf=none video=8000x4000 decode=8000x4000 drop=7 delayed=2 mistimed=0 avsync=0'
assert capture.extract(thermal) == ['playback-decode hwdec-current=videotoolbox drop=7 delayed=2 mistimed=0']
assert len(capture.extract('\n'.join([line]*10000))) == 24
assert capture.extract('file=/Users/person/private.mov [thermal-diag] unrelated') == []
assert capture.extract('14:37:19 gor-sample[6] top StretchGlyph /Users/private/file') == ['14:37:19 glyph-sample categories=StretchGlyph']
assert capture.extract('14:37:19 thread-cpu: win=10.0s threads=12 total=140% top[private]') == ['14:37:19 thread-cost win_s=10.0 threads=12 total_pct=140']
assert capture.extract('14:37:19 main-thread: win=10.0s busy=85% loops=51 counts[private]') == ['14:37:19 main-cost win_s=10.0 busy_pct=85 loops=51']
root = Path(__file__).resolve().parents[2]
source = _core_read(root/'Sources/gor/GorCore/Diag.swift').split('enum PlaybackProcessCPU {',1)[1]
harness = 'import Foundation\nenum PlaybackProcessCPU {'+source+'''
let snapshot = """
10 1 5.0 /Applications/gor
11 10 94.5 /app/vendor/mpv
12 10 130.5 /app/vendor/ffmpeg
13 12 40.0 /app/vendor/ffmpeg
14 99 999.0 /other/ffmpeg
15 10 200.0 /other/tool
malformed ignored
"""
let cost = PlaybackProcessCPU.parse(snapshot, rootPID: 10)
assert(cost.gor == 5.0 && cost.mpv == 94.5 && cost.ffmpeg == 170.5 && cost.workers == 2)
let empty = PlaybackProcessCPU.parse("", rootPID: 10)
assert(empty.gor == 0 && empty.mpv == 0 && empty.ffmpeg == 0 && empty.workers == 0)
print("PASS production child-tree CPU parser: includes nested children; excludes unrelated processes/arguments")
'''
with tempfile.TemporaryDirectory() as temp:
    swift = Path(temp)/'main.swift'; swift.write_text(harness)
    binary = Path(temp)/'test'
    subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'swiftc', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS numeric-only capped extractor (24 records, 128 KiB/source read)')
