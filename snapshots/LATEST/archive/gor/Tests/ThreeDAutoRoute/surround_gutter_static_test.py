#!/usr/bin/env python3
"""Static source test (no GPU): the 2D->3D pack path must not paint a fixed black
gap between the eyes, and Soft backing must also cover partial-coverage pixels
when Invert is off. Source text only; not a render, not Mac validation."""
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[2]
s=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
a=s.index('//192b automatic gutter');b=s.index('vec3 pl = pack_eye',a)
blk=s[a:b]
assert 'vec4(0,0,0,1)' not in blk,'pack gutter still paints fixed black'
assert 'pack_gutter=' in blk,'gutter flag not set'
assert 'coverage*=1.0-pack_gutter' in s,'film may leak into gutter'
m=re.search(r'if\(vr_pk_soft>0\.5 &&[^\n]*\n\s*background=pack_surround',s)
assert m and 'vr_pk_surround_invert>0.5' not in m.group(0) and 'coverage<1.0' in m.group(0),'soft backing gated on invert'
print('PASS surround gutter/partial-coverage static');sys.exit(0)
