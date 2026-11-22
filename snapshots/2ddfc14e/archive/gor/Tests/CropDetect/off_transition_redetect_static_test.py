#!/usr/bin/env python3
"""Source-text test (UNBUILT Swift): every route that leaves 3D for plain 2D must release the
menu's crop ownership and start automatic crop detection immediately. On 194p, offReset()
-> clearOwnedCropFromMenu() sets menuCropOwnsSelection=true and nothing restarted detection,
so startAutomaticCropDetection's guard blocked it until an unrelated event. Not a runtime test."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import re,sys
s=(_pp_split().path(Path(__file__).resolve().parents[2],'PPController.swift')).read_text()
h=s.find('private func redetectCropAfter3DOff()')
assert h>0,'no redetect-after-3D-off helper'
body=s[h:s.index('private func refreshCropSourcePacking',h)]
for need in ('menuCropOwnsSelection=false','cropDetector.resetLastFile()','startAutomaticCropDetection(needsRedetect:true)'):
    assert need in body,need
def span(sig):
    a=s.index(sig);return s[a:a+900]
for sig in ('func setVRModeEnabled(','func setVRModeManually(','func applyThreeDState(','func select3DOutput('):
    assert 'redetectCropAfter3DOff()' in span(sig),sig+' leaves 3D without redetect'
print('PASS 3D-off routes redetect crop (source text only)');sys.exit(0)
