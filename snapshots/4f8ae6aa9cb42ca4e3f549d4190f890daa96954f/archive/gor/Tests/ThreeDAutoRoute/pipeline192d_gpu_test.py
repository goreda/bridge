#!/usr/bin/env python3
"""192d D3-D5 actual Lua payload and generated GLSL sign, fusion and held scale."""
import math,numpy as np
from pathlib import Path
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/zoom_content_gpu_test.py'
exec(compile(f.read_text().split('for deg in (0,20,-20):')[0],str(f),'exec'))
# Actual payload must not add another filter or native FOV/translation bypass.
for native in (False,True):
 r=ns['Replay'](flat=not native)
 if native:r.msg('vr180-look-set-projection','vr180',16/9)
 r.msg('vr180-look-set-orientation',.1,-.2,123,.3,0,.04,-.03,0,'none','fov-unavailable',0,.301,.302)
 values=r.values()
 assert abs(values['vr_fov']-math.radians(123))<1e-6 and abs(values['vr_head_x']-.04)<1e-6
 assert abs(values['vr_head_roll']-(.302 if native else .3))<1e-6
 assert abs(values['vr_roll']-(.302 if native else .3))<1e-6
 print('PASS actual Lua native',native,'FOV/translation published exactly; flat film/fusion share final roll, native raw compatibility')
# Positive final pitch means head UP after Vision pitchSign=-1. Shader samples a higher source latitude, so a world-fixed feature moves DOWN.
for pitch in (-.1,.1):
 image=draw((w,h),dict(common,vr_pitch=pitch,vr_fov=math.radians(135),vr_head_z=0,vr_roll=0,vr_head_roll=0))
 eye=image[:,:w//2];weights=np.maximum(eye[:,:,2]-.05,0);yy,xx=np.indices(weights.shape)
 y=float((yy*weights).sum()/weights.sum())
 assert (y-h/2)*pitch<0,(pitch,y)
 print('PASS pitchSign=-1 at ScreenCaptureEngine rawPitch: final_pitch',pitch,'feature_y_GL',y,'positive look samples higher source latitude; world-fixed content shifts opposite camera')
ref=None;rows=[]
for deg in (0,20,30):
 roll=math.radians(deg);values=dict(vr_roll=roll,vr_head_roll=roll,vr_cross_eye=1,vr_fov=math.radians(135),vr_head_z=0)
 length,axis=measure(values)
 if ref is None:ref=length
 expected=axis[0]*math.tan(roll)
 assert abs(axis[1]-expected)<1
 scales=[]
 for noise in (-.001,0,.001):
  l,delta=measure(dict(values,vr_head_roll=roll+noise));scales.append(l/length)
  assert abs(delta[1]-delta[0]*math.tan(roll+noise))<1
 assert max(scales)-min(scales)<.002
 print('MEAS held_tilt_deg',deg,'scale_vs_level',length/ref,'filtered_roll_noise_scale_range',max(scales)-min(scales),'S1 residual_px',abs(axis[1]-expected))
 image=draw((w,h),dict(values,**common));rows.append((deg,image))
from PIL import Image,ImageDraw
canvas=Image.new('RGB',(960,len(rows)*624),(20,20,20));pen=ImageDraw.Draw(canvas)
for i,(deg,im) in enumerate(rows):
 pen.text((5,i*624+4),'held tilt '+str(deg)+'deg, fit policy retained',fill='white')
 canvas.paste(Image.fromarray((np.clip(im[::-1],0,1)*255).astype('uint8')),(0,i*624+24))
canvas.save('/downloads/192d-held-tilt.png')
print('PASS synthetic D3/D4/D5 shader tests. G1/G2/G5 owner traces NOT_MEASURED. Owner ruling keeps every corner; minimized geometric fit measured separately in divider_corners_gpu_test.')
