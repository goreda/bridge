#!/usr/bin/env python3
"""Portable R2/R4 checks. Dependencies: NumPy, lupa. No mpv/GPU claim."""
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
source = here.parents[1] / 'Resources/vendor/mpv/scripts/vr180-look.lua'
for gain in ('0.02', '0.04'):
    subprocess.run([sys.executable, str(here / 'test_roll_r4.py'), '--source', str(source), '--gain', gain], check=True)
subprocess.run([sys.executable, str(here / 'test_generated_sources.py'), str(source)], check=True)
subprocess.run([sys.executable, str(here / 'test_world_horizon.py'), str(source)], check=True)
from lupa import LuaRuntime
ok, error = LuaRuntime(unpack_returned_tuples=True).eval('function(s) local f,e=load(s);return f~=nil,e end')(source.read_text())
assert ok, error
with tempfile.TemporaryDirectory(prefix='r2-r4-') as directory:
    mutant = Path(directory) / 'arity-mutant.lua'
    text = source.read_text()
    bad = text.replace('stereo_pair_uv(uv,right,viewport_aspect,content,0.0)', 'stereo_pair_uv(uv,right,viewport_aspect,content)')
    assert bad != text
    mutant.write_text(bad)
    result = subprocess.run([sys.executable, str(here / 'test_generated_sources.py'), str(mutant)], text=True, capture_output=True)
    assert result.returncode != 0 and 'call arity' in result.stderr, result.stdout + result.stderr
print('PASS R2/R4 analytic checks, world-fixed horizon, actual Lua generators, full Lua compile, stale-call mutant assertion RED; GPU/pixels/mpv NOT_RUN')
