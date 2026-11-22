from pathlib import Path
import os,socket,json,time,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[2]
D=Path(os.environ['GOR_FIT_EVIDENCE_DIR']);D.mkdir(parents=True,exist_ok=True)
LETTER=os.environ.get('GOR_FIT_LETTER')=='1'
im=Image.new('RGB',(1920,1080),'black');d=ImageDraw.Draw(im);d.rectangle((234,0,1687,1079),fill=(40,170,90));d.rectangle((260,30,400,200),fill='red');
if LETTER:
 im=Image.new('RGB',(1920,1080),'black');d=ImageDraw.Draw(im);d.rectangle((0,140,1919,939),fill=(40,170,90));d.rectangle((30,160,180,300),fill='red')
im.save(D/'source.png')
gpu=['--gpu-sw=yes','--gpu-api=opengl','--gpu-context=x11egl'] if sys.platform!='darwin' else []
p=subprocess.Popen([os.environ['GOR_TEST_MPV'],'--no-config','--config-dir='+str(D),'--vo=gpu-next',*gpu,'--hwdec=no','--pause','--keep-open=yes','--force-window=yes','--no-border','--geometry='+('960x400' if LETTER else '728x540'),'--osd-level=0','--input-ipc-server='+str(D/'ipc'),str(D/'source.png')],stdout=open(D/'mpv.log','w'),stderr=subprocess.STDOUT)
try:
 for _ in range(200):
  if (D/'ipc').exists():break
  time.sleep(.03)
 s=socket.socket(socket.AF_UNIX);s.settimeout(15);s.connect(str(D/'ipc'));f=s.makefile('rb');rid=0
 def cmd(*a):
  global rid
  rid+=1;s.sendall((json.dumps(dict(command=a,request_id=rid))+'\n').encode())
  while True:
   row=json.loads(f.readline())
   if row.get('request_id')==rid:
    assert row['error']=='success',(a,row)
    return row.get('data')
 def expect_property(name,expected):
  # IPC command success acknowledges receipt, not the script's deferred apply.
  deadline=time.monotonic()+5
  while True:
   actual=cmd('get_property',name)
   if actual is expected:return
   assert time.monotonic()<deadline,(name,'state acknowledgement timeout',expected,actual)
   time.sleep(.05)
 def domain():
  msg('menu-crop',*(['1|.5|960','.7407407407|.5|400'] if LETTER else ['.7572916667|.5005208333|728','1|.5|540']))
  msg('bar-crop',*([0,140/1080,1,800/1080] if LETTER else [234/1920,0,1454/1920,1]))
 def msg(n,*a):cmd('script-message-to','vr180_look','vr180-look-'+n,*map(str,a));time.sleep(.1)
 def shot(name):
  time.sleep(.5);cmd('screenshot-to-file',str(D/(name+'.png')),'window')
  ar=np.asarray(Image.open(D/(name+'.png')).convert('RGB'));mask=ar[:,:,1]>100;ys,xs=np.where(mask);assert xs.min()<=2 and ys.min()<=2 and xs.max()>=ar.shape[1]-3 and ys.max()>=ar.shape[0]-3,(name,'unexpected double-fit inset',xs.min(),ys.min(),xs.max(),ys.max())
  print(name,'size',ar.shape,'green bounds',tuple(map(int,(xs.min(),ys.min(),xs.max(),ys.max()))),'keepaspect',cmd('get_property','keepaspect'),'osd',cmd('get_property','osd-dimensions'),flush=True)
 time.sleep(.7);cmd('load-script',str(R/'Resources/vendor/mpv/scripts/vr180-look.lua'));time.sleep(.4)
 cmd('set_property','video-crop',('1920x800+0+140' if LETTER else '1454x1080+234+0'));shot('before')
 cmd('set_property','video-crop','');domain();msg('tools-active','true');shot('head-on')
 for i in range(3):
  msg('tools-active','false');cmd('set_property','video-crop',('1920x800+0+140' if LETTER else '1454x1080+234+0'));shot('off'+str(i))
  cmd('set_property','video-crop','');domain();msg('tools-active','true');shot('on'+str(i))

 # Store-owned VR entry/Off resets tools; Swift can then re-enable tools on the plain film.
 msg('store-revision',1,'vr180','store-applier')
 msg('set-projection','vr180',1,1,'store-applier');msg('set-enabled','true',1,'store-applier')
 expect_property('keepaspect',False)
 msg('set-enabled','false',1,'store-applier');expect_property('keepaspect',True)
 domain();msg('tools-active','true');shot('vr-return-tools')
 msg('tools-active','false');expect_property('keepaspect',True)
 cmd('set_property','video-crop',('1920x800+0+140' if LETTER else '1454x1080+234+0'));shot('final-off')

finally:
 p.terminate();p.wait(timeout=10)
