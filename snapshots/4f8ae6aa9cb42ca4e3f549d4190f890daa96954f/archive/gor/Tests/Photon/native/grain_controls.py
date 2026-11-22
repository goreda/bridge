#!/usr/bin/env python3
"""Real pixel negative controls for the grain fixture; no production mutation.
Flat-field gate remains intact; zero strength must be exact off. The counterfactual
that removes the gate must fail flat-field equality, proving the negative is live.
"""
from pathlib import Path
import tempfile
import numpy as np
from PIL import Image
import grain_outcome as g
from sharp_outcome import render
p=Path(tempfile.mkdtemp(prefix='grain-controls-'))
coef,density=g.host(1080,1080);source=g.shader(coef,density)
assert '#define GRAIN_SIZE '+g.engine_constant('GRAIN_SIZE') in source
assert '#define GRAIN_SOFTNESS '+g.engine_constant('GRAIN_SOFTNESS') in source
for label,img in [('black',Image.new('RGB',(1920,1080),(0,0,0))),
                  ('flat',Image.new('RGB',(1920,1080),(128,128,128))),
                  ('detail',g.fixture(1080))]:
 ip=p/(label+'.png');img.save(ip)
 off=render(ip,1080,None,str(p/(label+'-off.png')),p)
 code=source
 if label=='detail': code=code.replace('#define BASE_STRENGTH %.4f'%g.ACCEPTED_STRENGTH,'#define BASE_STRENGTH 0.0000')
 sp=p/(label+'.glsl');sp.write_text(code)
 on=render(ip,1080,str(sp),str(p/(label+'-on.png')),p)
 assert np.array_equal(on,off),(label,float(np.abs(on-off).max()))
 print('PASS exact off pixels:',label, 'zero strength' if label=='detail' else 'flat-area gate')
# Near-flat 1-level detail is still low amplitude and exercises the live shader.
ip=p/'detail.png';sp=p/'active.glsl';sp.write_text(source)
a=render(ip,1080,str(sp),str(p/'active.png'),p)
o=render(ip,1080,None,str(p/'active-off.png'),p)
assert g.metrics(a,o,1080,1080)[0]>=g.VIS_MIN_LEVELS
print('PASS detail fixture exercises visible grain, unchanged visibility floor')
# Gate-removal negative: exact flat-field equality must detect its loss.
ip=p/'flat.png';sp=p/'no-gate.glsl'
sp.write_text(source.replace('luma_gain *= smoothstep(0.0, 1e-30, var);',''))
a=render(ip,1080,str(sp),str(p/'no-gate.png'),p)
o=render(ip,1080,None,str(p/'no-gate-off.png'),p)
assert not np.array_equal(a,o),'gate-removal negative was not detected'
print('PASS flat negative detects gate removal; no production shader changed')
print('pixel controls:',p)
