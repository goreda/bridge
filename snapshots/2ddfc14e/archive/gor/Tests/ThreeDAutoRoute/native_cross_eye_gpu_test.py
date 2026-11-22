#!/usr/bin/env python3
"""Native source-eye order at roll, actual Lua uniforms and generated GLSL pixels."""
from pathlib import Path
import math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/engine193b_gpu_test.py'
exec(compile(f.read_text().split('# Flat engines retain',1)[0],str(f),'exec'))
# Both eyes contain identical local gradients, distinguished solely by blue tag.
localx=(xx*2)%1
fixture=np.stack([.2+.6*localx,.2+.6*yy,np.where(xx<.5,.15,.85),np.ones_like(xx)],-1).astype('f4')
tex.write(fixture.tobytes())
for kind in ('vr180','vr180-tb'):
 if kind=='vr180-tb':
  fixture=np.stack([.2+.6*xx,.2+.6*((yy*2)%1),np.where(yy<.5,.15,.85),np.ones_like(xx)],-1).astype('f4');tex.write(fixture.tobytes())
 r=ns['Replay']();r.msg('vr180-look-set-projection',kind,1);r.msg('vr180-look-set-output','vr180');r.msg('vr180-look-set-enabled','true')
 prog=program(generated(current,True))
 for cross in (0,1):
  for source_swap in (0,1):
   swap=cross != source_swap
   r.msg('vr180-look-set-swap-eyes',str(int(swap)));r.msg('vr180-look-viewing-cross',str(cross))
   for deg in (-30,0,30):
    r.msg('vr180-look-set-orientation',0,0,119,math.radians(deg),0,0,0,0,'none','ok',.2,math.radians(deg),math.radians(deg))
    uniforms=r.values();assert uniforms['vr_swap_eyes']==int(swap) and uniforms['vr_cross_eye']==cross
    assert abs(uniforms['vr_roll']-math.radians(deg))<1e-6
    image=draw(prog,dict(uniforms,vr_gap_frac=0,vr_gap_blur_frac=0,vr_vignette_darken=0,vr_vignette_blur=0))
    for eye in (0,1):
     patch=image[h//2-3:h//2+3,eye*w//2+w//4-3:eye*w//2+w//4+3,2]
     expected=.85 if (eye != swap) else .15
     assert abs(float(np.median(patch))-expected)<.02,(kind,cross,source_swap,deg,eye,float(np.median(patch)),expected)
 print('PASS native generated pixels eye assignment at roll0,+-30, cross x source swap',kind)
print('PASS24native cross/swap/roll cases; does not establish perceptual fusion or camera identity on owner film')
