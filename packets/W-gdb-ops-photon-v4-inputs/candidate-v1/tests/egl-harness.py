#!/usr/bin/env python3
"""V4 calibration, derived flow from e119f893 card711-item68 EGL harness.
NOT mpv nor Metal. No hidden paths, no old variance-zero assertion.
"""
import os
os.environ.setdefault('EGL_PLATFORM','surfaceless')
os.environ.setdefault('LIBGL_ALWAYS_SOFTWARE','1')
os.environ.setdefault('GALLIUM_DRIVER','llvmpipe')
import argparse, hashlib, json
from pathlib import Path
import moderngl, numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
VERT='#version 330\nin vec2 p;out vec2 uv;void main(){uv=(p+1.0)/2.0;gl_Position=vec4(p,0,1);}'
class Rig:
 def __init__(self):
  self.ctx=moderngl.create_context(standalone=True,backend='egl')
  self.vbo=self.ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes())
 def render(self,src,frag,uniforms={}):
  h,w,_=src.shape;c=self.ctx
  prog=c.program(vertex_shader=VERT,fragment_shader=frag)
  tex=c.texture((w,h),4,np.ascontiguousarray(src,dtype='f4').tobytes(),dtype='f4');tex.filter=(moderngl.NEAREST,moderngl.NEAREST)
  target=c.texture((w,h),4,dtype='f4');fbo=c.framebuffer([target]);fbo.use();tex.use(0)
  if 'sourceTexture' in prog:prog['sourceTexture'].value=0
  for k,v in uniforms.items():
   if k in prog:prog[k].value=v
  vao=c.simple_vertex_array(prog,self.vbo,'p');vao.render(moderngl.TRIANGLE_STRIP)
  out=np.frombuffer(target.read(),dtype='f4').reshape(h,w,4).copy()
  for x in [vao,prog,tex,fbo,target]:x.release()
  assert np.isfinite(out).all(),'nonfinite'
  return out
 def controls(self,src):
  control='#version 330\nuniform sampler2D sourceTexture;in vec2 uv;out vec4 color;void main(){color=texture(sourceTexture,uv);%s}'
  assert np.array_equal(self.render(src,control%''),src),'identity'
  shift=self.render(src,control%'color.rgb+=0.1;')
  assert np.max(np.abs((shift-src)[:,:,:3]-0.1))<1e-6,'shift'
def width(delta):
 z=delta[8:-8,8:-8]; var=np.mean(z*z)
 for dx in range(1,65):
  r=np.mean(z[:,:-dx]*z[:,dx:])/var
  if r<0.5:return dx
 raise AssertionError('uncalibrated width >64')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',default='/tmp/photon-v4-egl');ap.add_argument('--quick',action='store_true');args=ap.parse_args()
 outdir=Path(args.out);outdir.mkdir(parents=True,exist_ok=True)
 shader=(ROOT/'shaders/grain.frag').read_text();rig=Rig();rows=[]
 # Seven fixture profiles ONLY synthetic calibration, not real corpus classes.
 profiles=[('sd-film-synthetic',480,1.0,.004),('720-film-synthetic',720,1.2,.003),('1080-grain-synthetic',1080,1.5,.02),('1080-clean-synthetic',1080,0,.0),('hdr-working-synthetic',2160,0,.001),('animation-flat-synthetic',1080,0,0),('mono-synthetic',1080,1.2,.002)]
 for name,sh,cell,source_sigma in profiles:
  for h in ([1080] if args.quick else [1080,1440,2160]):
   # 512-wide vertical ROI of declared picture height, full-height grain coords.
   w=512;src=np.ones((h,w,4),dtype='f4');src[:,:,:3]=.35
   rig.controls(src)
   cp=max(.6,(cell*h/sh if cell else .8*h/1080))
   u=dict(pictureRect=(0.,4.,float(w),float(h-8)),cellOutPixels=cp,ownerAmount=1.,ownerStrength=1.,compressionFactor=1.,minimumAddedFraction=.35,lumaKnots=(0.,.05,.15,.35,.55,.75,.9,1.),targetSigmaKnots=(.01,)*8,sourceSigmaKnots=(source_sigma,)*8,seed=198,frameBucket=4,enabled=1)
   rendered=rig.render(src,shader,u);repeat=rig.render(src,shader,u)
   assert np.array_equal(rendered,repeat),'determinism'
   assert np.array_equal(rendered[:4],src[:4]) and np.array_equal(rendered[-4:],src[-4:]),'bars'
   d=(rendered-src)[8:-8,8:-8,0];sigma=float(d.std());expected=max((max(.0001-source_sigma**2,0))**.5,.0035)
   assert abs(sigma/expected-1)<.10,(name,h,sigma,expected)
   assert sigma>0 and np.array_equal(rendered[:,:,0],rendered[:,:,1]) and np.array_equal(rendered[:,:,0],rendered[:,:,2]),'mono/positive'
   zero=rig.render(src,shader,dict(u,ownerAmount=0.));assert np.array_equal(zero,src),'manual zero'
   ac=width(d);row=dict(profile=name,fixture='generated flat .35, NOT real corpus',h=h,roi_width=w,cell=cp,sigma=sigma,target=expected,autocorr_half_px=ac,normalized_width=ac/cp)
   rows.append(row);print(json.dumps(row),flush=True)
   if name=='sd-film-synthetic' and h==1080:
    # Explicitly amplified only for inspection, not metric input.
    view=np.clip(rendered[:256,:512,:3],0,1);Image.fromarray((view*255).round().astype('uint8')).save(outdir/'grain.png')
    Image.fromarray((np.clip(.5+(rendered-src)[:256,:512,:3]*15,0,1)*255).astype('uint8')).save(outdir/'delta-x15.png')
 result=dict(renderer=rig.ctx.info['GL_RENDERER'],version=rig.ctx.info['GL_VERSION'],shader_sha256=hashlib.sha256(shader.encode()).hexdigest(),numpy=np.__version__,moderngl=moderngl.__version__,rows=rows,scope='EGL software calibration only, NOT mpv/Metal, NOT real 7-class corpus',autocorr_gate='measurement only until target calibrated')
 (outdir/'report.json').write_text(json.dumps(result,indent=2)+'\n')
 print('PASS',len(rows),'synthetic profiles/resolutions; autocorr reported, not accepted')
if __name__=='__main__':main()
