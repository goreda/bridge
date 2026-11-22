#!/usr/bin/env python3
"""Source-text test (UNBUILT Swift): the tracked-tilt subtitle safety canvas must be the cropped
film frame (local chromeBounds), not the display rect. On 194p it was displayRect, so a tilted
subtitle was only kept inside the whole video area, outside the film crop. Not a runtime test."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import sys
s=(_pp_split().path(Path(__file__).resolve().parents[2],'PPController.swift')).read_text()
i=s.index('subtitleView.setVRReplica(on: vrReplicating')
line=s[i:i+260]
assert 'screen:displayRect' not in line,'subtitle canvas is still displayRect'
assert 'subtitleFilmCanvas' in line
d=s[s.index('let subtitleFilmCanvas'):i]
assert 'committedFilmFrame != nil ? CGRect(origin:.zero,size:chromeBounds.size)' in d
assert 'subtitleView.frame = chromeBounds' in s
print('PASS subtitle safety canvas is the film frame (source text only)');sys.exit(0)
