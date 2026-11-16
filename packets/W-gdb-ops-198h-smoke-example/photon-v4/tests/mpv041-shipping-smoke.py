#!/usr/bin/env python3
import os,subprocess,tempfile,time,json
from pathlib import Path
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='photon041-shipping-')as tmp:
 t=Path(tmp);config=t/'config';config.mkdir();(config/'state').mkdir()
 Image.fromarray(np.full((128,128,3),100,dtype='uint8')).save(t/'src.png')
 display=os.environ.get('PHOTON_DISPLAY',':97');env=dict(os.environ,DISPLAY=display,LIBGL_ALWAYS_SOFTWARE='1')
 x=subprocess.Popen(['Xvfb',display,'-screen','0','800x600x24'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  time.sleep(.3)
  cmd=[os.environ['MPV'],'--no-config','--log-file='+str(t/'mpv.log'),'--vo=gpu-next','--gpu-context=x11egl','--gpu-sw=yes','--dither-depth=no','--ao=null','--pause','--keep-open=yes','--image-display-duration=inf','--screenshot-sw=no','--config-dir='+str(config),'--script-opts=photon-scriptdir='+str(root/'shipping')+',photon-smoke-out='+str(t/'smoke'),'--script='+str(root/'tests/mpv-sentinel/shipping-smoke.lua'),str(t/'src.png')]
  cmd+=['--script='+str(root/'shipping'/n)for n in ['photon.lua','photon-grain.lua','photon-sharp.lua']]
  p=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
  log=(t/'mpv.log').read_text();Path('/tmp/photon041-shipping.log').write_text(log)
  assert p.returncode==0,p.stdout.decode(errors='replace')
  assert not any(x in log for x in ['Lua error:','Unrecognized command','Error while parsing','compile log (status=0)','shader compilation failed']), '\n'.join(l for l in log.splitlines()if any(x in l for x in ['error','Error','failed','[f]','[e]']))
  rows=json.loads((t/'smoke.json').read_text())
  for row in rows:
   assert any(s.endswith('photon-grain.glsl')for s in row['shaders']),row
   assert any('photon-sharp' in s for s in row['shaders']),row
   assert row['hud'],'no round-trip HUD'
   a=np.frombuffer((t/('smoke-'+row['kind']+'.raw')).read_bytes(),dtype='uint8').reshape(row['h'],row['w'],4)[:,:,:3]
   row['sigma']=float((a@np.array([.2126,.7152,.0722])).std()/255)
  print([(r['kind'],r['sigma'])for r in rows]);assert rows[0]['sigma']>.001 and rows[1]['sigma']==0 and rows[2]['sigma']>rows[0]['sigma']*1.8,rows
  from PIL import ImageDraw
  panel=Image.new('RGB',(384,156),'white');draw=ImageDraw.Draw(panel)
  for i,row in enumerate(rows):
   a=np.frombuffer((t/('smoke-'+row['kind']+'.raw')).read_bytes(),dtype='uint8').reshape(row['h'],row['w'],4)[:,:,:3]
   panel.paste(Image.fromarray(a),(i*128,0));draw.text((i*128+4,135),row['kind']+' '+format(row['sigma'],'.4f'),fill='black')
  panel.save('/downloads/photon041-shipping-pixels.png')
  report={'scope':'Linux mpv0.41 gpu-next full modified three-script load/sharp+grain compile and injection/HUD roundtrip/live strength parameter mutation, not owner Mac/Darwin/built-app gate','rows':rows}
  Path('/tmp/photon041-shipping-proof.json').write_text(json.dumps(report,indent=2)+'\n');print(report['scope']+' rc0')
 finally:x.terminate();x.wait(timeout=5)
