#!/usr/bin/env python3
"""Live false-relief GPU test plus production prepared-depth mapper retention. Not Mac model execution."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import subprocess,tempfile,json,math,os,re
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
fp=ctx.program(vertex_shader=vs,fragment_shader=fs.replace('color=hook();','color=vec4(d3_depth(HOOKED_pos,0.5),0,0,1);'))
fv=ctx.simple_vertex_array(fp,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
fbo=ctx.simple_framebuffer((w,h),components=4,dtype='f4');fields=[]
for sign in [1,-1]:
 l=.5+sign*.4*np.cos(xx*6*np.pi)*np.cos(yy*2*np.pi)
 texture=np.stack([l,l,l,np.ones_like(l)],-1).astype('f4');tex.write(texture.tobytes());fbo.use();ctx.viewport=(0,0,w,h);fv.render(moderngl.TRIANGLE_STRIP)
 z=np.frombuffer(fbo.read(components=4,dtype='f4'),dtype='f4').reshape(h,w,4)[:,:,0].copy();fields.append(z)
 relief=np.ptp((z[h//2]-.5)*.04*w)
 print('MEAS live flat-texture false relief binocular_px',float(relief));assert relief<1e-4,'false texture waves'
contrast=float(np.max(np.abs(fields[0]-fields[1]))*.04*w)
print('MEAS contrast inversion disparity_delta_px',contrast);assert contrast<1e-4
# The stored VDA result is relative inverse depth, not metric ground truth.
# Use an explicit positive inverse-depth mapping for a retention test only.
depth=np.load(root/'tools/depth_analysis/kit/x2_tos_reference/tos_depth_minmax_320x180_fp16.npz')['depth'].astype('f4')
metric=1/(.1+depth[:,0,::12,::16].ravel())
head='''#include <cmath>
#include <cstdio>
using std::sqrt;using std::atan2;using std::asin;using std::tan;using std::floor;
using uint=unsigned int;
struct uint2 {uint x,y;};struct int2 {int x,y; int2(){} int2(int a,int b):x(a),y(b){}};
#define constant const
#define thread
#define M_PI_F 3.14159265f
struct S3DParams {float f,eye;uint w,h,ow,oh;float conv,znear;uint mode;float fout;};
'''
main='''int main(){float z;S3DParams p{160,0,320,180,320,180,0,.1,1,160};while(scanf("%f",&z)==1){int2 l,r;p.eye=-.0315;if(!s3d_map({160,90},p,z,l))return 2;p.eye=.0315;if(!s3d_map({160,90},p,z,r))return 3;printf("%d\\n",l.x-r.x);} }'''
def _kern(text):
 n='Stereo3DKernel.swift'
 return text[text.index('// BEGIN relocated '+n+' '):text.index('// END relocated '+n+'\n')]
sources=[_kern(subprocess.check_output(['git','show','HEAD:archive/gor/Sources/gor/gor/ThreeD.swift'],cwd=root,text=True)),_kern((_threed_split().path(root)).read_text())]
rows=[]
with tempfile.TemporaryDirectory() as d:
 for i,s in enumerate(sources):
  fun=s[s.index('    static bool s3d_map'):s.index('    kernel void s3d_clear')]
  p=Path(d)/('m'+str(i));p.with_suffix('.cpp').write_text(head+fun+main)
  subprocess.run(['g++','-std=c++17',str(p.with_suffix('.cpp')),'-o',str(p)],check=True)
  result=subprocess.check_output([str(p)],input='\n'.join(map(str,metric)),text=True)
  rows.append(np.array([float(v)for v in result.split()]))
  known=subprocess.check_output([str(p)],input='1\n4\n',text=True).split();print('MEAS known geometric near/far disparities_px',known)
  assert int(known[0])-int(known[1])>=6,'real geometric depth flattened'
 span0=np.ptp(np.percentile(rows[0],[5,95]));span1=np.ptp(np.percentile(rows[1],[5,95]));ratio=span1/span0
 print('MEAS recorded VDA fixture production mapper p5p95 disparity_px baseline/candidate/ratio',span0,span1,ratio)
 assert span0>1 and ratio>=.99 and np.array_equal(rows[0],rows[1]),'prepared structure lost'
print('PASS both software gates: false texture relief zero; actual prepared mapping retains nonzero recorded learned-depth structure. Mac registration/inference/playback NOT_RUN')
