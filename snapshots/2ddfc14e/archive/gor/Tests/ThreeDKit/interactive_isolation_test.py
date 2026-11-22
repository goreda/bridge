#!/usr/bin/env python3
"""Compiled production opt-in policy. Does not simulate native CPU/memory relief."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSelfTest.swift'+' '):_b.index('// END relocated '+'ThreeDSelfTest.swift'+'\n')])((_threed_split().path(root)).read_text()).split('#if canImport(AVFoundation)',1)[0]
main='''
precondition(!ThreeDSelfTest.interactiveRequested([:]))
precondition(!ThreeDSelfTest.interactiveRequested(["GOR_3D_INTERACTIVE_SELFTEST":"0"]))
precondition(!ThreeDSelfTest.interactiveRequested(["GOR_3D_INTERACTIVE_SELFTEST":"true"]))
precondition(ThreeDSelfTest.interactiveRequested(["GOR_3D_INTERACTIVE_SELFTEST":"1"]))
print("PASS interactive playback defaults to no synthetic model/render/telemetry workload; explicit diagnostic opt-in preserved")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(s+main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
kit=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDKit.swift'+' '):_b.index('// END relocated '+'ThreeDKit.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'guard enabled, ThreeDSelfTest.interactiveRequested(ProcessInfo.processInfo.environment)' in kit
cli=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSelfTestCLI.swift'+' '):_b.index('// END relocated '+'ThreeDSelfTestCLI.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'ThreeDSelfTest.run(' in cli and 'interactiveRequested' not in cli
print('PASS native interactive hook uses policy; explicit headless acceptance remains available')
