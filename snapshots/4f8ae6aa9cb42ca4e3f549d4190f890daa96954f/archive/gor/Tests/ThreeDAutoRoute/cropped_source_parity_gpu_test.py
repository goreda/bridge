#!/usr/bin/env python3
"""Same decoded crop rectangle, real GLSL: virtual domain equals physical source crop.
Analytical gradient eliminates resampling content differences. No Mac evidence.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import math,numpy as np,subprocess,tempfile,os,json
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
# Compile the real pixel-bound scanner, not a hand-written detector model.
scan=(lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(root)).read_text())
scan=scan[scan.index('enum SourcePixelBounds'):scan.index('final class SourcePixelCropScanner')]
program='import Foundation\n'+scan+'''
let w=1000,h=1000
var bytes=Data(count:w*h*2)
for y in 210..<840 {for x in 120..<830 {bytes[(y*w+x)*2]=200}}
let raw=SourcePixelBounds.scan(bytes,width:w,height:h,threshold:16)!
let b=SourcePixelBounds.outward(raw,width:w,height:h,stereo:false)
print("[\(Double(b.x0)/Double(w)),\(Double(b.y0)/Double(h)),\(Double(b.x1-b.x0)/Double(w)),\(Double(b.y1-b.y0)/Double(h))]")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'scan')],check=True)
 rect=json.loads(subprocess.check_output([str(p/'scan')],text=True))
cx,cy,cw,ch=rect
assert np.allclose(rect,(.12,.21,.71,.63))
print('Actual SourcePixelBounds scan/outward rectangle',rect)
reference=np.stack([.2+.5*xx,.3+.5*yy,.2+.2*xx+.1*yy,np.ones_like(xx)],-1).astype('f4')
source=np.stack([.2+.5*(xx-cx)/cw,.3+.5*(yy-cy)/ch,.2+.2*(xx-cx)/cw+.1*(yy-cy)/ch,np.ones_like(xx)],-1).astype('f4')
inside=(xx>=cx)&(xx<=cx+cw)&(yy>=cy)&(yy<=cy+ch);source[~inside,:3]=0
fails=[]
for pack in (0,3):
 for deg in (0,25,-45):
  for gain,convergence in ((0,0),(.04,0),(.04,.4)):
   v=dict(vr_pack=pack,vr_flat_mono=1,vr_flat_sbs=1,vr_source_layout=0,vr_roll=math.radians(deg),vr_head_roll=math.radians(deg),vr_fov=math.radians(135),vr_pk_soft=0,vr_d3_gain=gain,vr_base_ipd=convergence,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=0)
   tex.write(reference.tobytes());a=draw((960,540),dict(v,vr_eye_aspect=16/9*cw/ch,vr_source_x=0,vr_source_y=0,vr_source_w=1,vr_source_h=1))
   tex.write(source.tobytes());b=draw((960,540),dict(v,vr_eye_aspect=16/9,vr_source_x=cx,vr_source_y=cy,vr_source_w=cw,vr_source_h=ch))
   # Compare interior content, excluding edge filtering and coverage AA.
   mask=(a.min(-1)>.2)&(b.min(-1)>.2)
   error=np.abs(a-b)[mask];maximum=float(error.max());mean=float(error.mean())
   print('same crop vs physical crop',pack,deg,gain,convergence,'max',maximum,'mean',mean)
   if maximum>.003:fails.append((pack,deg,gain,convergence,maximum,mean))
# Decisive pixel evidence from the final asymmetric -45 degree fixture.
from PIL import Image,ImageDraw
panel=Image.new('RGB',(960,3*540+90),'#202020');label=ImageDraw.Draw(panel)
for row,(name,image) in enumerate([('Physical crop reference',a),('Same accepted detector rect in original source',b),('Absolute RGB difference x20',np.abs(a-b)*20)]):
 panel.paste(Image.fromarray(np.uint8(np.clip(image,0,1)*255)),(0,row*570+30));label.text((12,row*570+8),name,fill='white')
panel.save('/tmp/crop-domain-parity.png')
assert not fails,fails
print('PASS exact crop-domain coordinate parity: physical cropped source == same source rect in converted SBS')
