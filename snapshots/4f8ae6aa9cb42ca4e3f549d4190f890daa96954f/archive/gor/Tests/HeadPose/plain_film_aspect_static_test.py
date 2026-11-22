#!/usr/bin/env python3
"""Source-text test for 194q: plain 2D keeps the film aspect and bounds the rotated film
rectangle. Red on 194p (no vr_plain_aspect). Not a render, not Mac validation."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
s=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
assert '//!PARAM vr_plain_aspect' in s,'plain film aspect uniform missing'
assert '/vr_plain_aspect=%.6f' in s,'Lua does not publish film aspect'
a=s.index('    if(vr_plain>0.5) {\n        vec2 uv=surface_pos');b=s.index('    if (vr_flat_sbs > 0.5) {',a)
blk=s[a:b]
for need in ('plain_content','uv/=plain_content','film_w','film_h'):
    assert need in blk,need
assert 'float asp=out_size.x/out_size.y;\n        //194i' not in blk
assert blk.index('uv=mat2(cr,sr,-sr,cr)*uv')<blk.index('uv/=plain_content'),'content division must follow the physical rotation'
assert 'uv*=vr_frame_fit>0.0 ? 1.0/vr_frame_fit:max(1.0,rotate_bound);' in blk,'shader must use the published fit as given, no extra shrink'
assert s.count('plain_film_aspect(')>=3,'film_frame_snapshot and payload must share plain_film_aspect'
assert 'video-params/dw' in s and 'video-params/par' in s,'decoded/SAR fallback missing'
snap=s[s.index('local function film_frame_snapshot'):s.index('local function vr_push_uniforms')]
assert 'plain_film_aspect(override)' in snap and 'frameW=plain and cx' in snap and 'panx=-px*cx*scale' in snap,'published plain frame still uses the surface'
print('PASS plain film aspect static');sys.exit(0)
