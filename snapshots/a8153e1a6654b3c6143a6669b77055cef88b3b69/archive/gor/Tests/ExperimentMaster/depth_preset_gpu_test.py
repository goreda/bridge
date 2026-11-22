#!/usr/bin/env python3
"""Actual generated Lua shader software-EGL pixels: tuned preset versus previous D, off baseline unchanged."""
from pathlib import Path
import runpy,subprocess
import numpy as np
from PIL import Image,ImageDraw
r=Path(__file__).resolve().parents[2]
ns=runpy.run_path(str(r/'Tests/ThreeDAutoRoute/d3_budget_gpu_test.py'))
new=ns['new'];new.mode(True,0);new.budget.on=True
new.budget.conv=0;new.budget.comp=.35
p,v=ns['compile_pack'](new.budget.source(new.pack))
# draw() has globals in the imported helper's namespace, not this runpy dict.
g=ns['draw'].__globals__;g['prog']=p;g['vao']=v
frame=np.stack([.15+.7*ns['xx'],.15+.7*ns['yy'],.2+.5*((np.floor(ns['xx']*16)+np.floor(ns['yy']*10))%2),np.ones_like(ns['xx'])],-1).astype('f4')
ns['tex'].write(frame.tobytes());tuned=ns['draw']((ns['w'],ns['h']),ns['settings'])
previous=subprocess.check_output(['git','show','9f86509b1:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],cwd=r,text=True)
_,prev=ns['ns']['load'](previous,True);prev.mode(True,0);prev.budget.on=True;prev.budget.conv=-.08;prev.budget.comp=.65
p,v=ns['compile_pack'](prev.budget.source(prev.pack));g['prog']=p;g['vao']=v
prior=ns['draw']((ns['w'],ns['h']),ns['settings'])
assert np.isfinite(tuned).all() and np.abs(tuned-prior).mean()>0
f=new.budget.map
# Within existing clamps, positive/negative mid-depth separation increases, midpoint moves nearer.
oldspan=prev.budget.map(.002,-.08,.65,.01,.005,.0075)-prev.budget.map(-.002,-.08,.65,.01,.005,.0075)
newspan=f(.002,0,.35,.01,.005,.0075)-f(-.002,0,.35,.01,.005,.0075)
assert newspan>0 and f(0,0,.35,.01,.005,.0075)==0
# A linear depth ramp must have constant first differences, hence straight lines.
ramp=np.array([f(float(d),0,.35,.01,.005,.0075) for d in np.linspace(-.002,.002,101)])
curvature=float(np.max(np.abs(np.diff(ramp,2))))
oldramp=np.array([prev.budget.map(float(d),-.08,.65,.01,.005,.0075) for d in np.linspace(-.002,.002,101)])
oldcurve=float(np.max(np.abs(np.diff(oldramp,2))))
assert curvature<1e-12 and oldcurve>1e-9
print('MEAS plane curvature second difference old',oldcurve,'affine',curvature)
for d in np.linspace(-.04,.04,1000):assert -.0075<=f(float(d),0,.35,.01,.005,.0075)<=.005
print('MEAS separation old',oldspan,'preset',newspan,'pixel meanabs',float(np.abs(tuned-prior).mean()),'caps unchanged')
w,h=ns['w'],ns['h'];out=Image.new('RGB',(w*2,h+25));draw=ImageDraw.Draw(out)
for i,(label,img) in enumerate([('Previous D: conv-.08 comp.65',prior),('Affine preset: conv0 comp.35',tuned)]):
 out.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')),(i*w,25));draw.text((i*w+4,5),label,fill='white')
import os,tempfile
outpath=os.environ.get('GOR_DEPTH_PRESET_PIXELS') or str(Path(tempfile.gettempdir())/'195j-affine-depth-preset.png')
out.save(outpath);print('pixels saved:',outpath)
print('PASS generated preset pixels; synthetic fixture only, not owner film or AppKit/Mac')
