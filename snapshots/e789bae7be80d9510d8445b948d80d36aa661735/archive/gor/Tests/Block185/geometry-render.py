from pathlib import Path
import os,socket,json,subprocess,time,tempfile
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2];out=Path(os.environ.get('GOR_GEOMETRY_OUTPUT','/tmp/gor185-geometry-pixels'));out.mkdir(exist_ok=True)
def c(sock,*args):
 with socket.socket(socket.AF_UNIX) as s:
  s.settimeout(12);s.connect(str(sock));s.sendall(json.dumps({'command':list(args)}).encode()+b'\n');buf=b''
  while True:
   buf+=s.recv(65536)
   while b'\n' in buf:
    a,buf=buf.split(b'\n',1);j=json.loads(a)
    if 'error' in j:return j
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp)
 for packing in ['flat-sbs','flat-tb','vr180']:
  im=Image.new('RGB',(960,480));dr=ImageDraw.Draw(im)
  for eye in [0,1]:
   box=(0,eye*240,960,(eye+1)*240) if packing=='flat-tb' else (eye*480,0,(eye+1)*480,480)
   dr.rectangle(box,fill=(180,30,40) if eye==0 else (20,140,210));x0,y0,x1,y1=box
   for k in range(1,8):dr.line((x0+(x1-x0)*k/8,y0,x0+(x1-x0)*k/8,y1),fill=(240,240,240),width=3)
   dr.ellipse((x0+(x1-x0)*.25,y0+(y1-y0)*.25,x0+(x1-x0)*.75,y0+(y1-y0)*.75),outline='yellow',width=7)
  img=d/(packing+'.png');im.save(img)
  sock=d/(packing+'.sock');cfg=d/(packing+'cfg');cfg.mkdir()
  with open(out/(packing+'.log'),'w') as log:
   proc=subprocess.Popen([os.environ.get('GOR_TEST_MPV',str(root/'Resources/vendor/mpv/bin/mpv')),'--no-config','--config-dir='+str(cfg),'--script='+str(root/'Resources/vendor/mpv/scripts/vr180-look.lua'),'--vo=gpu-next','--gpu-context=x11egl','--gpu-sw=yes','--ao=null','--no-audio','--pause','--image-display-duration=inf','--keep-open=yes','--force-window=yes','--no-osc','--no-border','--geometry=960x480','--dither-depth=no','--input-ipc-server='+str(sock),str(img)],stdout=log,stderr=log)
   try:
    for _ in range(120):
     if sock.exists():
      try:
       if c(sock,'get_property','dwidth').get('data'):break
      except Exception:pass
     time.sleep(.1)
    def msg(*a):
     z=c(sock,'script-message-to','vr180_look',*map(str,a));assert z['error']=='success',z;return z
    msg('vr180-look-set-projection',packing,'2.0');msg('vr180-look-set-enabled','true');time.sleep(1)
    for name,x,y,ar in [('identity',1,1,0),('crop',.75,1,0),('aspect',1,1,1.5),('reset',1,1,0)]:
     c(sock,'set_property','video-aspect-override',ar);msg('vr180-look-menu-crop',x,y);time.sleep(.8)
     z=c(sock,'screenshot-to-file',str(out/(packing+'-'+name+'.png')),'window');assert z['error']=='success',z
    shader=list((cfg/'shader').glob('*.glsl'));assert shader
   finally:
    proc.terminate();proc.wait(timeout=12)
import numpy as np
for p in ['flat-sbs','flat-tb','vr180']:
 a=np.asarray(Image.open(out/(p+'-identity.png')).convert('RGB'));b=np.asarray(Image.open(out/(p+'-reset.png')).convert('RGB'));assert np.array_equal(a,b),(p,'resetpixels')
 crop=np.asarray(Image.open(out/(p+'-crop.png')).convert('RGB'));assert np.any(a!=crop),(p,'cropmustchange')
 if p!='vr180':
  for name in ['identity','crop','aspect','reset']:
   v=np.asarray(Image.open(out/(p+'-'+name+'.png')).convert('RGB'));h,w=v.shape[:2];l=v[h//2,w//4];r=v[h//2,3*w//4];assert l[0]>l[2] and r[2]>r[0],(p,name,l,r)
 print('PASS actualproductionmpv',p,'cropchangespixels/resetexact/pairretained')
imgs=[Image.open(out/(p+'-'+n+'.png')).convert('RGB').resize((320,160)) for p in ['flat-sbs','flat-tb','vr180'] for n in ['identity','crop','aspect','reset']]
contact=Image.new('RGB',(1280,540),'#222');draw=ImageDraw.Draw(contact)
for i,im in enumerate(imgs):x=i%4*320;y=i//4*180;contact.paste(im,(x,y+20));draw.text((x+5,y+3),['flat-sbs','flat-tb','vr180'][i//4]+' '+['identity','crop','aspect','reset'][i%4],fill='white')
contact.save(out/'contact.png')
