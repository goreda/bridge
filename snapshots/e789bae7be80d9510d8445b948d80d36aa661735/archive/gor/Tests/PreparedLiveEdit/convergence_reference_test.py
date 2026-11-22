"""arch-194b4c: CPU reference, fixed per-eye shift is not bit-exact.
No claim about native Metal, VT or Mac gpu-next uniform support.
"""
from pathlib import Path
import sys,math
import numpy as np
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tools/depth_analysis'))
# Only the perspective eye reference is used, never the cv2 pack/downsample path.
try: import cv2
except ImportError:
 import types
 sys.modules['cv2']=types.ModuleType('cv2')
import output_modes as om
fx=root/'tools/depth_analysis/golden/mode_fixture'
rgb=np.load(fx/'rgb.npy');z=np.load(fx/'z.npy');theta=.9075712110370514
# The current flat renderer floors source splats before visibility and hole fill.
# Even a perfectly chosen post-encode translation cannot recover those samples.
for sign in (-1,1):
 a=om.render_eye(rgb,z,theta,sign=sign,convergence_m=1.5)
 b=om.render_eye(rgb,z,theta,sign=sign,convergence_m=2.0)
 f=(a.shape[1]/2)/math.tan(math.radians(75)/2)
 delta=f*(sign*.063/2)*(1/2.0-1/1.5)
 x=np.arange(a.shape[1])-delta;lo=np.floor(x).astype(int);frac=(x-lo)[None,:,None]
 shifted=np.clip(np.round(a[:,np.clip(lo,0,a.shape[1]-1)].astype(float)*(1-frac)+a[:,np.clip(lo+1,0,a.shape[1]-1)].astype(float)*frac),0,255).astype('uint8')
 bad=int(np.any(shifted!=b,axis=2).sum())
 print('MEAS convergence CPU reference sign',sign,'delta',delta,'mismatched_pixels',bad,'of',b.shape[0]*b.shape[1])
 assert bad>0,'this fixture no longer rejects post-encode shift'
print('PASS convergence joins shot-boundary re-render per4d; no live-shift equivalence claimed')
