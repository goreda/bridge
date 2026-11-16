#!/usr/bin/env python3
"""Bounded real-content EGL run. Results do not certify Mac/mpv/P22 playback.
Requires fixture manifest and local files whose hashes match. Missing/unknown
class or metadata stays pending, never substituted with a synthetic flat.
"""
import argparse,hashlib,importlib.util,json,subprocess
from pathlib import Path
from fractions import Fraction
import numpy as np
from PIL import Image
from scipy.ndimage import uniform_filter
spec=importlib.util.spec_from_file_location('rig',Path(__file__).with_name('egl-harness.py'));rigmodule=importlib.util.module_from_spec(spec);spec.loader.exec_module(rigmodule)
K=np.array([0,.05,.15,.35,.55,.75,.9,1.]);T=np.array([.0015,.003,.006,.01,.01,.007,.004,.002])
def source_measure(rgb):
 y=rgb@np.array([.2126,.7152,.0722]);s=uniform_filter(y,size=5,mode='nearest')
 gx=abs(np.roll(s,1,1)-np.roll(s,-1,1));gy=abs(np.roll(s,1,0)-np.roll(s,-1,0))
 mask=(np.maximum(gx,gy)<=.02);mask[:3]=False;mask[-3:]=False;mask[:,:3]=False;mask[:,-3:]=False
 residual=y-s;bins=np.clip((s*8).astype('int'),0,7);counts=[];sigmas=[]
 for b in range(8):
  z=residual[mask&(bins==b)];counts.append(len(z));sigmas.append(float(z.std(ddof=1)) if len(z)>=32 else None)
 valid=np.array([i for i,z in enumerate(sigmas) if z is not None]);assert len(valid),'no supported decoded luma bin'
 knots=np.interp(K,(valid+.5)/8,np.array([sigmas[i] for i in valid]))
 return knots,dict(counts=counts,sigma=sigmas,scope='decoded RGB source minus5x5 spatial mean; no sharp/grain; correlation-size fit pending')
def decode(path,time,height=None):
 cmd=['ffmpeg','-v','error','-ss',str(time),'-i',str(path),'-frames:v','1']
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,color_transfer,color_primaries,pix_fmt,sample_aspect_ratio','-of','json',str(path)]))['streams'][0]
 w,h=probe['width'],probe['height']
 if height:
  sar=probe.get('sample_aspect_ratio','1:1');sar=Fraction(sar.replace(':','/')) if sar not in ['N/A','0:1'] else Fraction(1);w=int(round(w*float(sar)*height/h/2)*2);h=height;cmd+=['-vf',f'scale={w}:{h}:flags=lanczos']
 data=subprocess.check_output(cmd+['-f','rawvideo','-pix_fmt','rgb48le','-'])
 return np.frombuffer(data,dtype='<u2').reshape(h,w,3).astype('float32')/65535.,probe
def main():
 a=argparse.ArgumentParser();a.add_argument('--manifest',required=True);a.add_argument('--out',required=True);args=a.parse_args()
 manifest=Path(args.manifest);d=json.loads(manifest.read_text());root=manifest.parent;rig=rigmodule.Rig();rows=[]
 shader=(rigmodule.ROOT/'shaders/grain.frag').read_text()
 for fixture in d['rows']:
  path=root/fixture['file'];assert hashlib.sha256(path.read_bytes()).hexdigest()==fixture['actual_fixture_sha256'],fixture['id']+' hash mismatch'
  time=fixture.get('fixture_timepoint_seconds',fixture['timepoint_seconds']);source,probe=decode(path,time);source_knots,measurement=source_measure(source)
  for h in [1080,1440,2160]:
   rgb,_=decode(path,time,h);cx=rgb.shape[1]//2;rgb=rgb[:,max(0,cx-256):cx+256];w=rgb.shape[1]
   src=np.ones((h,w,4),dtype='f4');src[:,:,:3]=rgb;rig.controls(src)
   cell=max(.6,.8*h/1080) # look-mode while est_src/confidence are uncalibrated
   u=dict(pictureRect=(0.,0.,float(w),float(h)),cellOutPixels=cell,ownerAmount=1.,ownerStrength=1.,compressionFactor=1.,minimumAddedFraction=.35,lumaKnots=tuple(K),targetSigmaKnots=tuple(T),sourceSigmaKnots=tuple(source_knots),seed=198,frameBucket=4,enabled=1)
   result=rig.render(src,shader,u);repeat=rig.render(src,shader,u);assert np.array_equal(result,repeat),'determinism'
   delta=(result-src)[:,:,0];y=rgb@np.array([.2126,.7152,.0722]);target=np.interp(y,K,T);noise=np.interp(y,K,source_knots);expected=np.sqrt(np.maximum(target*target-noise*noise,.35*.35*target*target))
   if h==1080:
    # Working-signal preview, not HDR display tone-map. Delta multiplied15 for inspection.
    preview=np.concatenate([src[128:384,:,:3],result[128:384,:,:3],.5+(result-src)[128:384,:,:3]*15],axis=1)
    Image.fromarray((np.clip(preview,0,1)*255).round().astype('uint8')).save(Path(args.out).parent/(fixture['id']+'-preview.png'))
   normalized=delta/expected;bins=np.clip((y*8).astype('int'),0,7);metrics=[]
   for b in range(8):
    m=bins==b;n=int(m.sum())
    if n>=2048:
     measured=float(delta[m].std());want=float(np.sqrt(np.mean(expected[m]**2)));assert abs(measured/want-1)<.10,(fixture['id'],h,b,measured,want)
     metrics.append(dict(bin=b,count=n,sigma=measured,target_rms=want,status='PASS'))
    else:metrics.append(dict(bin=b,count=n,status='UNOBSERVED'))
   assert np.array_equal(rig.render(src,shader,dict(u,ownerAmount=0)),src),'manual zero'
   row=dict(id=fixture['id'],class_name=fixture['class_name'],h=h,source_size=[probe['width'],probe['height']],source_transfer=probe.get('color_transfer','UNKNOWN'),measurement=measurement,cell=cell,bins=metrics,normalized_autocorr_half_px=rigmodule.width(normalized)/cell)
   rows.append(row);print(json.dumps(row),flush=True)
 report=dict(shader_sha256=hashlib.sha256(shader.encode()).hexdigest(),renderer=rig.ctx.info['GL_RENDERER'],scope='real content, EGL llvmpipe only; bins UNOBSERVED are NOT passed; width reported not accepted; look-mode only; not application/native acceptance',rows=rows)
 Path(args.out).write_text(json.dumps(report,indent=2)+'\n');print('REAL EGL rows',len(rows),'rc0; width and missing bins explicitly pending')
if __name__=='__main__':main()
